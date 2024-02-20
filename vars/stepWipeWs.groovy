def call(String workspace) {
	// params
	// workspace: Jenkins workspace to wipe

	echo "Entering stepWipeWs with parameter ${workspace}"

	sh "find ${workspace} -mindepth 1 -delete"
}
