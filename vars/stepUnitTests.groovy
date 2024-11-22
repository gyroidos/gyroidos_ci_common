def call(Map target) {
	// params
	// workspace: Absolute path to Yocto workspace
	// sourcedir: Directory containing 'cml' git

	echo "Entering stepUnitTests with parameters\n\tsourcedir ${target.sourcedir},\n\tworkspace: ${target.workspace}"

	script {
		sh 'echo "Performing unit tests"'
	}

	sh label: 'Clean CML Repo', script: "git -C ${target.sourcedir} clean -fx"

	testscript = libraryResource('unit-testing.sh')	
	writeFile file: "${target.workspace}/unit-testing.sh", text: "${testscript}"

	sh label: 'Perform unit tests', script: """
		cd ${target.sourcedir}/common/testdata && bash gen_testvectors.sh

		bash ${target.workspace}/unit-testing.sh ${target.sourcedir}
	"""
}
