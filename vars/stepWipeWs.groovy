def call(String workspace, String manifest_path) {
	// params
	// workspace: Jenkins workspace to wipe

	echo "Entering stepWipeWs with parameter ${workspace}"

	sh 'id'

	sh "find ${workspace} -mindepth 1 ! -wholename '${manifest_path}*' -print -delete"
}
