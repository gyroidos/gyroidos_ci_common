def call(Map target) {
	// params
	// workspace: workspace to operate on
	// build_number: Build number to store


    // workaround for missing ability to retrieve build number from CopyArtifacts plugin as suggested in JENKINS-34620
    writeFile file: "${target.workspace}/.build_number", text: "${target.build_number}"

    archiveArtifacts artifacts: ".build_number" , fingerprint: true, allowEmptyArchive: false

	echo "Recorded build number: ${target.build_number}"
}
