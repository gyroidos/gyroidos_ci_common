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

	stepWipeWs(target.workspace, target.manifest_path)

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
		elif [ "production" = "${target.buildtype}" ];then
			echo "Preparing Yocto workdir for production build"
			DEVELOPMENT_BUILD=n
			TRUSTME_PLAIN_DATAPART="1"
		elif [ "ccmode" = "${target.buildtype}" ];then
			echo "Preparing Yocto workdir for CC Mode build"
			DEVELOPMENT_BUILD=n
			ENABLE_SCHSM="1"
			CC_MODE=y
			TRUSTME_PLAIN_DATAPART="1"
		elif [ "schsm" = "${target.buildtype}" ];then
			echo "Preparing Yocto workdir for dev mode build with schsm support"
			ENABLE_SCHSM="1"
		elif [ "asan" = "${BUILDTYPE}" ];then
			echo "Preparing Yocto workdir for dev mode build with sanitizers enabled"
			ENABLE_SCHSM="1"
			TRUSTME_SANITIZERS="1"
			git clone https://github.com/gyroidos/meta-tmedbg
		else
			echo "Error, unkown ${target.buildtype}, exiting..."
			exit 1
		fi

		if [ -d out-${target.buildtype}/conf ]; then
			rm -r out-${target.buildtype}/conf
		fi

		. trustme/build/yocto/init_ws_ids.sh out-${target.buildtype} ${target.gyroid_arch} ${target.gyroid_machine}

		if  [ "asan" = "${BUILDTYPE}" ];then
			echo "Preparing workspace for build with ASAN, ${WORKSPACE}/out-${BUILDTYPE}"
			bash  ${WORKSPACE}/meta-tmedbg/prepare_ws.sh  ${WORKSPACE}/out-${BUILDTYPE}
		fi


		cd ${target.workspace}/out-${target.buildtype}

		MIRRORPATH="/yocto_mirror/${target.yocto_version}/${target.gyroid_machine}/"

		echo "INHERIT += \\\"own-mirrors\\\"" >> conf/local.conf
		echo "SOURCE_MIRROR_URL = \\\"file:///\$MIRRORPATH/sources/\\\"" >> conf/local.conf
		echo "BB_GENERATE_MIRROR_TARBALLS = \\\"1\\\"" >> conf/local.conf

		if [ "y" = "${target.sync_mirrors}" ];then
			echo "Not using sstate cache for mirror sync"
		else
			echo "SSTATE_MIRRORS =+ \\\"file://.* file:///\$MIRRORPATH/sstate-cache/${target.buildtype}/PATH\\\"" >> conf/local.conf
		fi

		echo "BB_SIGNATURE_HANDLER = \\\"OEBasicHash\\\"" >> conf/local.conf
		echo "BB_HASHSERVE = \\\"\\\"" >> conf/local.conf

		echo 'TRUSTME_DATAPART_EXTRA_SPACE="10000"' >> conf/local.conf

		if [[ "apalis-imx8 tqma8mpxl" =~ "${GYROID_MACHINE}" ]]; then
			# when building for NXP machines you have to accept the Freescale EULA
			echo 'ACCEPT_FSL_EULA = "1"' >> conf/local.conf
		fi

		cat conf/local.conf

		bitbake trustx-cml-initramfs multiconfig:container:trustx-core
		bitbake trustx-cml

		if [ "y" = "${target.build_installer}" ];then
			 bitbake multiconfig:installer:trustx-installer
		fi
	"""


	stepStoreRevisions(workspace: target.workspace, buildtype: "${target.buildtype}", manifest_path: target.manifest_path, manifest_name: target.manifest_name)

	sh label: 'Compress trustmeimage.img', script: "xz -T 0 -f out-${target.buildtype}/tmp/deploy/images/*/trustme_image/trustmeimage.img --keep"

	if (target.containsKey("build_installer") && "y" == target.build_installer) {
		sh label: 'Compress trustmeinstaller.img', script: "xz -T 0 -f out-${target.buildtype}/tmp_installer/deploy/images/**/trustme_image/trustmeinstaller.img --keep"
	}

	if (target.containsKey("sync_mirrors") && "y" == target.sync_mirrors) {
		stepSyncMirrors(workspace: "${target.workspace}", yocto_version: "${target.yocto_version}", gyroid_machine: "${target.gyroid_machine}",  buildtype: "${target.buildtype}", build_number: "${BUILD_NUMBER}")
	}

	archiveArtifacts artifacts: "out-${target.buildtype}/tmp/deploy/images/**/trustme_image/trustmeimage.img.xz, \
				       out-${target.buildtype}/tmp_installer/deploy/images/**/trustme_image/trustmeinstaller.img.xz, \
				       out-${target.buildtype}/test_certificates/**, \
				       out-${target.buildtype}/tmp/deploy/images/**/ssh-keys/**, \
				       out-${target.buildtype}/tmp/deploy/images/**/cml_updates/kernel-**.tar, \
					   out-${target.buildtype}/tmp/work/**/cmld/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/protobuf-c-text/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/sc-hsm-embedded/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/service-static/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/cml-boot/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/cml-boot/**/image/init, \
					   out-${target.buildtype}/tmp/work/**/linux-rolling-stable/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/trustx-cml/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/trustx-cml-firmware/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/trustx-cml-initramfs/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/trustx-cml-modules/**/temp/**, \
					   out-${target.buildtype}/conf/**, \
					   out-${target.buildtype}/tmp/log/**, .build_number" , fingerprint: true, allowEmptyArchive: false
}
