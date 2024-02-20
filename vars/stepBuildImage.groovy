def call(Map target) {
	// params
	// workspace: Jenkins workspace to operate on
	// manifest_path: Path to manifest to store revisions after build
	// manifest_name: Name of manifest to initialize workspace
	// gyroid_arch: GyroidOS architecture, used to determine manifest
	// gyroid_machine: GyroidOS machine type, used to determine manifest
	// buildtype: Type of image to build
	// selector: Build selector for CopyArtifact step
	// build_installer: Specifies whether installer image should be built
	// sync_mirrors: Specifies whether source and sstate mirrors should be synced
	// rebuild_previous: Specifies whether sources should be built again
	// 					 when running pipeline on a previous build


	echo "Running on host: ${NODE_NAME}"

	echo "Entering stepBuildImage with parameters:\n\tworkspace: ${target.workspace}\n\tmanifest_path: ${target.manifest_path}\n\tmanifest_name: ${target.manifest_name}\n\tgyroid_arch: ${target.gyroid_arch}\n\tgyroid_machine: ${target.gyroid_machine}\n\tbuildtype: ${target.buildtype}\n\tselector: ${buildParameter('BUILDSELECTOR')}\n\tbuild_installer: ${target.build_installer}\n\tsync_mirrors: ${target.sync_mirrors}\n\trebuild_previous: ${target.rebuild_previous}"

	stepWipeWs(target.workspace)

	def artifact_build_no = utilGetArtifactBuildNo(workspace: target.workspace, selector: target.selector)

	if (("${BUILD_NUMBER}" != "${artifact_build_no}") && ("n" == "${target.rebuild_previous}")) {
		echo "Selected build different from the current one (${BUILD_NUMBER} vs. ${artifact_build_no}), skipping image build"
		return
	}

    step ([$class: 'CopyArtifact',
        projectName: env.JOB_NAME,
        selector: target.selector,
        filter: "sources-${target.gyroid_arch}-${target.gyroid_machine}.tar, .build_number",
        flatten: true]);

	sh "echo \"Unpacking sources${target.gyroid_arch}-${target.gyroid_machine}\" && tar -C \"${target.workspace}\" -xf sources-${target.gyroid_arch}-${target.gyroid_machine}.tar"
 

	sh label: 'Perform Yocto build', script: """
		export LC_ALL=en_US.UTF-8
		export LANG=en_US.UTF-8
		export LANGUAGE=en_US.UTF-8

		if [ "dev" = ${target.buildtype} ];then
			echo "Preparing Yocto workdir for development build"
			SANITIZERS=y
		elif [ "production" = "${target.buildtype}" ];then
			echo "Preparing Yocto workdir for production build"
			DEVELOPMENT_BUILD=n
		elif [ "ccmode" = "${target.buildtype}" ];then
			echo "Preparing Yocto workdir for CC Mode build"
			DEVELOPMENT_BUILD=n
			ENABLE_SCHSM="1"
			CC_MODE=y
		elif [ "schsm" = "${target.buildtype}" ];then
			echo "Preparing Yocto workdir for dev mode build with schsm support"
			SANITIZERS=y
			ENABLE_SCHSM="1"
		else
			echo "Error, unkown ${target.buildtype}, exiting..."
			exit 1
		fi

		if [ -d out-${target.buildtype}/conf ]; then
			rm -r out-${target.buildtype}/conf
		fi

		. trustme/build/yocto/init_ws_ids.sh out-${target.buildtype} ${target.gyroid_arch} ${target.gyroid_machine}

		cd ${target.workspace}/out-${target.buildtype}

		echo "INHERIT += \\\"own-mirrors\\\"" >> conf/local.conf
		echo "SOURCE_MIRROR_URL = \\\"file:///source_mirror\\\"" >> conf/local.conf
		echo "BB_GENERATE_MIRROR_TARBALLS = \\\"1\\\"" >> conf/local.conf

		if [ "n" = "${target.sync_mirrors}" ];then
			echo "SSTATE_MIRRORS =+ \\\"file://.* file:///sstate_mirror/${target.buildtype}/PATH\\\"" >> conf/local.conf
		else
			echo "Not using sstate cache for mirror sync"
		fi

		echo "BB_SIGNATURE_HANDLER = \\\"OEBasicHash\\\"" >> conf/local.conf
		echo "BB_HASHSERVE = \\\"\\\"" >> conf/local.conf

		cat conf/local.conf


		echo 'TRUSTME_DATAPART_EXTRA_SPACE="3000"' >> conf/local.conf

		bitbake trustx-cml-initramfs multiconfig:container:trustx-core
		bitbake trustx-cml

		if [ "y" = "${target.build_installer}" ];then
			 bitbake multiconfig:installer:trustx-installer
		fi
	"""


	stepStoreRevisions(workspace: target.workspace, buildtype: "${target.buildtype}", manifest_path: target.manifest_path, manifest_name: target.manifest_name)

	sh label: 'Compress trustmeimage.img', script: "xz -T 0 -f out-${target.buildtype}/tmp/deploy/images/*/trustme_image/trustmeimage.img --keep"

	if (target.containsKey("build_installer") && "y" == target.build_installer) {
		sh label: 'Compress trustmeinstaller.img', script: "xz -T 0 -f out-${target.buildtype}/tmp/deploy/images/**/trustme_image/trustmeinstaller.img --keep"
	}

	if (target.containsKey("sync_mirrors") && "y" == target.sync_mirrors) {
		stepSyncMirrors(workspace: "${target.workspace}", yocto_version: "${target.yocto_version}", gyroid_arch: "${target.gyroid_arch}",  buildtype: "${target.buildtype}", build_number: "${BUILD_NUMBER}")
	}

	archiveArtifacts artifacts: "out-${target.buildtype}/tmp/deploy/images/**/trustme_image/trustmeimage.img.xz, \
				       out-${target.buildtype}/tmp/deploy/images/**/trustme_image/trustmeinstaller.img.xz, \
				       out-${target.buildtype}/test_certificates/**, \
				       out-${target.buildtype}/tmp/deploy/images/**/ssh-keys/**, \
				       out-${target.buildtype}/tmp/deploy/images/**/cml_updates/kernel-**.tar, .build_number" , fingerprint: true, allowEmptyArchive: false
}
