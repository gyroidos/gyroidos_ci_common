def call(Map target = [:]) {
	// params
	// workspace: Jenkins workspace to operate on
	// yocto_version: Yocto version to sync mirrors for, e.g. 'kirkstone'
	// gyroid_machine: GyroidOS maschine, used to determine mirror path
	// buildytpe: Build type to sync mirrors for, e.g. 'dev'


	echo "Running on host: ${NODE_NAME}"

	catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
		echo "Entering stepSyncMirrors with parameters:\n\tworkspace: ${target.workspace}\n\tyocto_version: ${target.yocto_version}\n\tgyroid_machine: ${target.gyroid_machine}\n\tbuildtype: ${target.buildtype}"

		sh label: 'Syncing mirrors', script: """
			MIRRORPATH="/yocto_mirror/${target.yocto_version}/${target.gyroid_machine}/"

			SSTATE="\$MIRRORPATH/sstate-cache/${target.buildtype}"
			SOURCES="\$MIRRORPATH/sources/"
			ATTIC="\$MIRRORPATH/attic_sstate/${target.buildtype}/\$(TZ=UTC date +%Y%m%d_%H%M%S)_${target.buildtype}"
			TARPATH="\$ATTIC/sstate_${target.buildtype}.tar"

			rsync -v -e "ssh -v -l jenkins-ssh" -r --ignore-existing --no-devices --no-specials --no-links "${target.workspace}/out-${target.buildtype}/downloads/" ${env.MIRRORHOST}:"\$SOURCES"

			ssh -v jenkins-ssh@${env.MIRRORHOST} "mkdir \$ATTIC"

			ssh -v jenkins-ssh@${env.MIRRORHOST} "find \$SSTATE -mindepth 1 -maxdepth 1 -exec mv '{}' \$ATTIC \\;"

			tar -C "${target.workspace}/out-${target.buildtype}/sstate-cache/" -cf "${target.workspace}/sstate_${target.buildtype}.tar" .

			rsync -v -e "ssh -v -l jenkins-ssh" "sstate_${target.buildtype}.tar" ${env.MIRRORHOST}:"\$TARPATH"

			ssh -v jenkins-ssh@${env.MIRRORHOST} "cd \$SSTATE && tar -xf \$TARPATH"
		"""
	}
}
