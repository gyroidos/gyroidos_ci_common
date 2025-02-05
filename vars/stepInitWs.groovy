def call(Map target = [:]) {
	// params
	// workspace: Jenkins workspace to operate on
	// manifest_path: Path to/URL of repository containing manifest
	// manifest_name: Name of manifest to initialize workspace
	// gyroid_arch: GyroidOS architecture, used to determine manifest
	// gyroid_machine: GyroidOS machine type, used to determine manifest
	// selector: Build selector for CopyArtifact step
	// rebuild_previous: Specifies whether sources should be built again
	// 					 when running pipeline on a previous build
	// pr_branches: Comma separated list of pull requests for specific repos that
	//	should override the default branch

	echo "Running on host: ${NODE_NAME}"

	echo "Entering stepInitWs with parameters:\n\t workspace: ${target.workspace}\n\t manifest_path: ${target.manifest_path}\n\tmanifest_name: ${target.manifest_name}\n\tgyroid_arch: ${target.gyroid_arch}\n\tgyroid_machine: ${target.gyroid_machine}\n\tselector: ${buildParameter('BUILDSELECTOR')}\n\trebuild_previous: ${target.rebuild_previous}"

	utilArchiveBuildNo(workspace: target.workspace, build_number: BUILD_NUMBER)

	def artifact_build_no = utilGetArtifactBuildNo(workspace: target.workspace, selector: target.selector)

	if (("${BUILD_NUMBER}" != "${artifact_build_no}")) {
		echo "Selected build different from the current one (${BUILD_NUMBER} vs. ${artifact_build_no}), skipping stepInitWs()"

		return
	}

	stepWipeWs(target.workspace, target.manifest_path)

	sh label: 'Repo init', script: """
		cd ${target.workspace}/.manifests
		git rev-parse --verify jenkins-ci && git branch -D jenkins-ci
		git checkout -b "jenkins-ci"

		cd ${target.workspace}
		repo init --depth=1 -u ${target.manifest_path} -b "jenkins-ci" -m ${target.manifest_name}
	"""

	sh label: 'Parse PRs + repo sync', script: """
		mkdir -p .repo/local_manifests

		meta_repos="meta-gyroidos|meta-gyroidos-intel|meta-gyroidos-rpi|meta-gyroidos-nxp"
		cml_repo="cml"
		build_repo="gyroidos_build"
		branch_regex="PR-([0-9]+)"

		echo "${target.pr_branches}" | tr ',' '\n' | while read -r line; do
			if [[ "\$line" =~ (\$meta_repos)=\$branch_regex ]]; then
				project="\${BASH_REMATCH[1]}"
				revision="refs/pull/\${BASH_REMATCH[2]}/merge"

				echo "\
<?xml version=\\\"1.0\\\" encoding=\\\"UTF-8\\\"?>\n\
<manifest>\n\
<remove-project name=\\\"\$project\\\" />\n\
<project path=\\\"\$project\\\" name=\\\"\$project\\\" remote=\\\"gyroidos\\\" revision=\\\"\$revision\\\" />\n\
</manifest>" >> .repo/local_manifests/\$project.xml
			elif [[ "\$line" =~ (\$cml_repo)=\$branch_regex ]]; then
				project="\${BASH_REMATCH[1]}"
				revision="refs/pull/\${BASH_REMATCH[2]}/merge"

				echo "\
<?xml version=\\\"1.0\\\" encoding=\\\"UTF-8\\\"?>\n\
<manifest>\n\
<remove-project name=\\\"\$project\\\" />\n\
<project path=\\\"gyroidos/cml\\\" name=\\\"\$project\\\" remote=\\\"gyroidos\\\" revision=\\\"\$revision\\\" />\n\
</manifest>" >> .repo/local_manifests/\$project.xml
			elif [[ "\$line" =~ (\$build_repo)=\$branch_regex ]]; then
				project="\${BASH_REMATCH[1]}"
				revision="refs/pull/\${BASH_REMATCH[2]}/merge"

				echo "\
<?xml version=\\\"1.0\\\" encoding=\\\"UTF-8\\\"?>\n\
<manifest>\n\
<remove-project name=\\\"\$project\\\" />\n\
<project path=\\\"gyroidos/build\\\" name=\\\"\$project\\\" remote=\\\"gyroidos\\\" revision=\\\"\$revision\\\" />\n\
</manifest>" >> .repo/local_manifests/\$project.xml
			else
				echo "Could not parse revision for line \$line"
			fi
		done

		repo sync -j8 --current-branch --fail-fast

	"""

	sh "tar -C \"${target.workspace}\" -cf \"${target.workspace}/sources-${target.gyroid_arch}-${target.gyroid_machine}.tar\" --exclude=sources-${target.gyroid_arch}-${target.gyroid_machine}.tar ."

	archiveArtifacts artifacts: "sources-${target.gyroid_arch}-${target.gyroid_machine}.tar" , fingerprint: true, allowEmptyArchive: false
}
