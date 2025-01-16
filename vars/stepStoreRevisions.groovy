def call(Map target) {
	// params
	// workspace: workspace to operate on
	// buildtype: current build type
	// manifest_path: absolute path to manifest to operate on

	echo "Entering stepStoreRevisions with parameters workspace: ${target.workspace},\n\tbuildytpe: ${target.buildtype},\n\tmanifest_path: ${target.manifest_path}"

	testscript = libraryResource('store-revisions.sh')	
	writeFile file: "${target.workspace}/store-revisions.sh", text: "${testscript}"

	sh label: 'Creating manifest_revisions.xml and auto.conf', script: """

	mkdir "${target.workspace}/out-${target.buildtype}/gyroidos_revisions"

	# if kernel was linux-rolling-stable, pin its version
	rolling_srcrev="\$(find "${target.workspace}/out-${target.buildtype}" -wholename '*/linux-rolling-stable/latest_srcrev')"
	if [ -n "\$rolling_srcrev" ];then
		rolling_stable=--rolling-stable
	else
		rolling_stable=
	fi

	bash "${target.workspace}/store-revisions.sh" -w "${target.workspace}" -m "${target.manifest_path}/${target.manifest_name}" -o "${target.workspace}/out-${target.buildtype}/gyroidos_revisions" -b "${target.workspace}/out-${target.buildtype}/buildhistory" --cml \$rolling_stable
	"""

	sh "ls -al ${target.workspace}/"

	archiveArtifacts artifacts: "out-${target.buildtype}/gyroidos_revisions/**" , fingerprint: true, allowEmptyArchive: false 
}
