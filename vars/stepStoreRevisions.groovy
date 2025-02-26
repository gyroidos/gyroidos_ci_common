def call(Map target) {
	// params
	// workspace: workspace to operate on
	// buildtype: current build type
	// manifest_path: absolute path to manifest to operate on
	// gyroid_machine: GyroidOS machine being build

	echo "Entering stepStoreRevisions with parameters workspace: ${target.workspace},\n\tbuildytpe: ${target.buildtype},\n\tmanifest_path: ${target.manifest_path}\n\tgyroid_machine: ${target.gyroid_machine}"

	testscript = libraryResource('store-revisions.sh')	
	writeFile file: "${target.workspace}/store-revisions.sh", text: "${testscript}"

	sh label: 'Creating manifest_revisions.xml and auto.conf', script: """

	mkdir "${target.workspace}/out-${target.buildtype}/gyroidos_revisions"

	bash "${target.workspace}/store-revisions.sh" -w "${target.workspace}" -m "${target.manifest_path}/${target.manifest_name}" -o "${target.workspace}/out-${target.buildtype}/gyroidos_revisions" -b "${target.workspace}/out-${target.buildtype}/buildhistory" --cml --gyroid_machine "${gyroid_machine}"
	"""

	sh "ls -al ${target.workspace}/"

	archiveArtifacts artifacts: "out-${target.buildtype}/gyroidos_revisions/**" , fingerprint: true, allowEmptyArchive: false 
}
