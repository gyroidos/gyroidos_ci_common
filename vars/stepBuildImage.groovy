import org.jenkinsci.plugins.pipeline.modeldefinition.Utils

def call(Map target) {
	// params
	// workspace: Jenkins workspace to operate on
	// mirror_base_path: Base path for source and sstate mirrors
	// manifest_path: Path to manifest to store revisions after build
	// manifest_name: Name of manifest to initialize workspace
	// gyroid_arch: GyroidOS architecture, used to determine manifest
	// gyroid_machine: GyroidOS machine type, used to determine manifest
	// buildtype: Type of image to build
	// selector: Build selector for CopyArtifact step
	// build_installer: Specifies whether installer image should be built
	// sync_mirrors: Specifies how to connect to source and sstate mirrors for sync
	// rebuild_previous: Specifies whether sources should be built again
	// 					 when running pipeline on a previous build
	// hookPreBuild: Executed before building the image
	// hookPostBuild: Executed after building the image
	// pki: Path to PKI to be used for build
	// pki_passwd: PKI password


	echo "Running on host: ${NODE_NAME}"

	echo "Entering stepBuildImage with parameters:\n\tworkspace: ${target.workspace}\n\tmirror_base_path: ${target.mirror_base_path}\n\tmanifest_path: ${target.manifest_path}\n\tmanifest_name: ${target.manifest_name}\n\tgyroid_arch: ${target.gyroid_arch}\n\tgyroid_machine: ${target.gyroid_machine}\n\tbuildtype: ${target.buildtype}\n\tselector: ${buildParameter('BUILDSELECTOR')}\n\tbuild_installer: ${target.build_installer}\n\tsync_mirrors: ${target.sync_mirrors}\n\trebuild_previous: ${target.rebuild_previous}\n\thookPreBuild provided: ${target.containsKey("hookPreBuild") ? "yes" : "no" } \n\tbuild_coreos: ${target.build_coreos}\n\tpki: ${target.pki}"

	stepWipeWs(target.workspace, target.manifest_path)

	def artifact_build_no = utilGetArtifactBuildNo(workspace: target.workspace, selector: target.selector)

	if (("${BUILD_NUMBER}" != "${artifact_build_no}") && ("n" == "${target.rebuild_previous}")) {
		echo "Selected build (${artifact_build_no}) different from the current one (${BUILD_NUMBER}), skipping image build"
		Utils.markStageSkippedForConditional(target.stage_name);
		return
	}

    step ([$class: 'CopyArtifact',
        projectName: env.JOB_NAME,
        selector: target.selector,
        filter: "sources-${target.gyroid_arch}-${target.gyroid_machine}.tar, .build_number",
        flatten: true]);

	sh "echo \"Unpacking sources${target.gyroid_arch}-${target.gyroid_machine}\" && tar -C \"${target.workspace}\" -xf sources-${target.gyroid_arch}-${target.gyroid_machine}.tar"

	script {
		env.DEVELOPMENT_BUILD = "${("production" == target.buildtype) || ("ccmode" == target.buildtype) ? 'n' : 'y'}"
		env.CC_MODE = "${("ccmode" == target.buildtype) || ("schsm" == target.buildtype) ? 'y' : 'n'}"
		env.ENABLE_SCHSM = "1"
		env.GYROIDOS_SANITIZERS = "${("asan" == target.buildtype) ? '1' : '0'}"
		env.GYROIDOS_PLAIN_DATAPART = "${("production" == target.buildtype) || ("ccmode" == target.buildtype) || ("schsm" == target.buildtype) ? '1' : '0'}"

		sh label: 'Prepare build directory', script: """
			export LC_ALL=en_US.UTF-8
			export LANG=en_US.UTF-8
			export LANGUAGE=en_US.UTF-8

			echo "Workspace preparation environment:"
			env


			cd ${target.workspace}/

			. gyroidos/build/yocto/init_ws_ids.sh out-${target.buildtype} ${target.gyroid_arch} ${target.gyroid_machine}

			if  [ "asan" = "${BUILDTYPE}" ];then
				cd ${target.workspace}/

				echo "Preparing workspace for build with ASAN, ${WORKSPACE}/out-${BUILDTYPE}"
				bash  ${WORKSPACE}/meta-tmedbg/prepare_ws.sh  ${WORKSPACE}/out-${BUILDTYPE}

				cd ${target.workspace}/out-${target.buildtype}
			fi

			MIRRORPATH="${target.mirror_base_path}/${target.yocto_version}/${target.gyroid_machine}/"

			echo 'GYROIDOS_DATAPART_EXTRA_SPACE="20000"' >> conf/local.conf

			echo "INHERIT += \\\"own-mirrors\\\"" >> conf/local.conf
			echo "SOURCE_MIRROR_URL = \\\"file://${target.mirror_base_path}/sources/\\\"" >> conf/local.conf
			echo "BB_GENERATE_MIRROR_TARBALLS = \\\"1\\\"" >> conf/local.conf

			if [ "y" == "${target.sync_mirrors}" ];then
				echo "Not using sstate cache for mirror sync"
			else
				echo "SSTATE_MIRRORS =+ \\\"file://.* file://\$MIRRORPATH/sstate-cache/${target.buildtype}/PATH\\\"" >> conf/local.conf
			fi

			echo "Using source cache at ${target.mirror_base_path}/sources/"
			echo "Using sstate cache at \$MIRRORPATH/sstate-cache/${target.buildtype}/"

			echo "BB_SIGNATURE_HANDLER = \\\"OEBasicHash\\\"" >> conf/local.conf
			echo "BB_HASHSERVE = \\\"\\\"" >> conf/local.conf

			if [[ "apalis-imx8 tqma8mpxl" =~ "${GYROID_MACHINE}" ]]; then
				# when building for NXP machines you have to accept the Freescale EULA
				echo 'ACCEPT_FSL_EULA = "1"' >> conf/local.conf
			fi

			cat conf/local.conf
		"""

		if (target.containsKey("hookPreBuild") && null != target.hookPreBuild) {
			echo "Executing hookPreBuild"
			target.hookPreBuild(target.workspace, target.buildtype)
		} else {
			echo "No hookPreBuild specified"
		}



		sh label: 'Perform Yocto build', script: """
			echo "Build environment:"
			env

			if ! [ -z "${target.pki} "];then
				echo "Using PKI at ${target.pki}"
				ln -s /yocto_mirror/gyroidos_release_pki ${target.workspace}/out-${target.buildtype}/test_certificates

				ls -al ${target.workspace}/out-${target.buildtype}/test_certificates

				if ! [ -z "${target.pki_passwd}" ];then
					export KBUILD_SIGN_PIN="${target.pki_passwd}"
					export GYROIDOS_TEST_PASSWD_PKI="${target.pki_passwd}"
				fi
			else
				echo "No PKI specified, new one will be generated"
			fi

			. gyroidos/build/yocto/init_ws_ids.sh out-${target.buildtype} ${target.gyroid_arch} ${target.gyroid_machine}

			if [ "true" = "${target.build_coreos}" ];then
				echo "Building gyroidos-core"
				bitbake multiconfig:container:gyroidos-core
			else
				echo "Skipping build of gyroidos-core as requested"
			fi

			bitbake gyroidos-cml

			
			if [ "y" = "${target.build_installer}" ];then
				 bitbake multiconfig:installer:gyroidos-installer
			fi
		"""
	}

	stepStoreRevisions(workspace: target.workspace, buildtype: "${target.buildtype}", manifest_path: target.manifest_path, manifest_name: target.manifest_name, gyroid_machine: target.gyroid_machine)

	sh label: 'Compress gyroidosimage.img', script: "xz -T 0 -f out-${target.buildtype}/tmp/deploy/images/*/gyroidos_image/gyroidosimage.img --keep"

	if (target.containsKey("build_installer") && "y" == target.build_installer) {
		sh label: 'Compress gyroidosinstaller.img', script: "xz -T 0 -f out-${target.buildtype}/tmp_installer/deploy/images/**/gyroidos_image/gyroidosinstaller.img --keep"
	}

	if (target.containsKey("sync_mirrors") && "y" == target.sync_mirrors) {
		stepSyncMirrors(workspace: target.workspace, mirror_base_path: target.mirror_base_path, yocto_version: target.yocto_version, gyroid_machine: target.gyroid_machine,  buildtype: target.buildtype, build_number: BUILD_NUMBER)
	}

	archiveArtifacts artifacts: "out-${target.buildtype}/tmp/deploy/images/**/gyroidos_image/gyroidosimage.img.xz, \
				       out-${target.buildtype}/tmp_installer/deploy/images/**/gyroidos_image/gyroidosinstaller.img.xz, \
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
					   out-${target.buildtype}/tmp/work/**/gyroidos-cml/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/gyroidos-cml/**/rootfs/userdata/cml/device.conf, \
					   out-${target.buildtype}/tmp/work/**/gyroidos-cml-firmware/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/gyroidos-cml-initramfs/**/temp/**, \
					   out-${target.buildtype}/tmp/work/**/gyroidos-cml-modules/**/temp/**, \
					   out-${target.buildtype}/conf/**, \
					   out-${target.buildtype}/tmp/log/**, .build_number" , fingerprint: true, allowEmptyArchive: false
}
