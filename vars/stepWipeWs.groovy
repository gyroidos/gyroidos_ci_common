def call(String workspace, String manifest_path) {
	sh """
		set -euxo pipefail
		echo "Clearing '${workspace}' of anything that is not manifests."
		
		FILEFILE="\$(mktemp /tmp/gyroid_filelist.XXXXX)"
		STASHTARBALL="\$(mktemp "\$(dirname "${workspace}")/ws_stash.XXXXXX")"
		trap 'rm -f "\$FILEFILE" "\$STASHTARBALL"' EXIT
		
		# Find all manifest files
		env -C "${workspace}" find . -mindepth 1 -maxdepth 1 -name '.manifests*' -fprint0 "\$FILEFILE"
		
		# Stash them
		tar --no-dereference -cf "\$STASHTARBALL" -C "${workspace}" --null --files-from="\$FILEFILE"
		
		# Wipe workspace contents
		env -C "${workspace}" find . -mindepth 1 -maxdepth 1 -exec rm -rf {} +
		
		# Restore stash
		tar --no-dereference -xf "\$STASHTARBALL" -C "${workspace}"
	"""
}
