def call(Map target) {
	// params
	// workspace: Absolute path to Yocto workspace
	// sourcedir: Directory containing 'cml' git


	echo "Entering stepFormatCheck with parameters\n\tsourcedir ${target.sourcedir},\n\tworkspace: ${target.workspace}"
	sh label: 'Clean CML Repo', script: "git -C ${target.sourcedir} clean -fx"

	checkscript = libraryResource('check-if-code-is-formatted.sh')	
	writeFile file: "${target.workspace}/check-if-code-is-formatted.sh", text: "${checkscript}"	

	sh label: 'Check code formatting', script: "bash ${target.workspace}/check-if-code-is-formatted.sh ${target.sourcedir}"
}
