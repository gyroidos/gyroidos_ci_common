def call(Map target) {
	// params
	// workspace: workspace to operate on
	// selector: Selector for CopyArtifact step


    // workaround for missing ability to retrieve build number from CopyArtifacts plugin as suggested in JENKINS-34620
    step ([$class: 'CopyArtifact',
        projectName: env.JOB_NAME,
        selector: target.selector,
        filter: ".build_number",
        flatten: true]);

    
    def build_number = readFile file: "${target.workspace}/.build_number"

	return build_number
}
