def call(Map target) {
	// params
	// workspace: Absolute path to Yocto workspace
	// sourcedir: Directory containing 'cml' git


	echo "Entering stepFormatCheck with parameters\n\tsourcedir ${target.sourcedir},\n\tworkspace: ${target.workspace}"
	sh label: 'Clean CML Repo', script: "git -C ${target.sourcedir} clean -fx"

	writeFile file: "${target.workspace}/common.sh", text: libraryResource('common.sh')
	writeFile file: "${target.workspace}/check-if-code-is-formatted.sh", text: libraryResource('check-if-code-is-formatted.sh')

	sh label: 'Check code formatting', script: "bash ${target.workspace}/check-if-code-is-formatted.sh ${target.sourcedir}"
}
