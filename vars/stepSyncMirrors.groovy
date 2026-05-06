def call(Map target = [:]) {
	// params
	// workspace: Jenkins workspace to operate on
	// mirror_base_path: Base path for source and sstate mirrors
	// yocto_version: Yocto version to sync mirrors for, e.g. 'kirkstone'
	// gyroid_machine: GyroidOS maschine, used to determine mirror path
	// buildytpe: Build type to sync mirrors for, e.g. 'dev'


	echo "Running on host: ${NODE_NAME}"

	catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
		echo "Entering stepSyncMirrors with parameters:\n\tworkspace: ${target.workspace}\n\tssh_cmd: ssh -v\n\tmirror_base_path: ${target.mirror_base_path}\n\tyocto_version: ${target.yocto_version}\n\tgyroid_machine: ${target.gyroid_machine}\n\tbuildtype: ${target.buildtype}"

		sh label: 'Local mirror sync', script: """
			set -eu
			do_rsync() { rsync -ah --info=stats2 --no-links --no-devices --no-specials "\$@"; }
			MIRRORPATH="${target.mirror_base_path}/${target.yocto_version}/${target.gyroid_machine}/"
			SSTATE="\$MIRRORPATH/sstate-cache/${target.buildtype}"

			mkdir -p "\$SSTATE"
			do_rsync --ignore-existing '${target.workspace}/out-${target.buildtype}/downloads/' '${target.mirror_base_path}/sources'
			do_rsync '${target.workspace}/out-${target.buildtype}/sstate-cache/' "\$SSTATE"
		"""
	}
}
