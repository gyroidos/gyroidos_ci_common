def call(String workspace, String manifest_path) {
	sh """
		echo "Clearing '${workspace}' of anything that is not manifests."
		env -C "${workspace}" find . -mindepth 1 -maxdepth 1 ! -name '.manifests*' -exec rm -rf {} +
	"""
}
