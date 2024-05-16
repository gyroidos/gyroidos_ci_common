import groovy.transform.Field
import org.jenkinsci.plugins.pipeline.modeldefinition.Utils

def integrationTestX86(Map target = [:]) {

	stepWipeWs(target.workspace)

	script {
		if ((! target.containsKey("workspace")) || (! target.containsKey("buildtype")) || (! target.containsKey("schsm_serial")) || (! target.containsKey("schsm_pin"))) {
			error("Missing keys in map 'target'")
		}

		step ([$class: 'CopyArtifact',
			projectName: env.JOB_NAME,
			selector: target.selector,
			filter: "out-${target.buildtype}/**/trustmeimage.img.xz, sources-${target.gyroid_arch}-${target.gyroid_machine}.tar",
			flatten: true]);


		dir("${target.workspace}/test_certificates") {
			step ([$class: 'CopyArtifact',
				projectName: env.JOB_NAME,
				selector: target.selector,
				filter: "out-${target.buildtype}/test_certificates/**",
				flatten: true]);
		}


		def artifact_build_no = utilGetArtifactBuildNo(workspace: target.workspace, selector: target.selector)

		echo "Using stash of build number determined by selector: ${artifact_build_no}"

		sh "echo \"Unpacking sources\" && tar -C \"${target.workspace}\" -xf sources-${target.gyroid_arch}-${target.gyroid_machine}.tar"

		sh label: "Extract image", script: 'unxz -T0 trustmeimage.img.xz'

		if (target.schsm_serial) {
			schsm_opts="--enable-schsm ${target.schsm_serial} ${target.schsm_pin}"
			test_mode="dev"
		} else {
			schsm_opts=""
			test_mode="${target.buildtype}"
		}
	
		testscript = libraryResource('VM-container-tests.sh')	
		testcommands = libraryResource('VM-container-commands.sh')	

		writeFile file: "${target.workspace}/VM-container-tests.sh", text: "${testscript}"
		writeFile file: "${target.workspace}/VM-container-commands.sh", text: "${testcommands}"

		sh label: "Perform integration test", script: """
			bash ${target.workspace}/VM-container-tests.sh --mode "${test_mode}" --dir "${target.workspace}" --image trustmeimage.img --pki "${target.workspace}/test_certificates" --name "testvm" --ssh 2222 --kill --vnc 1 --log-dir "${target.workspace}/cml_logs" ${schsm_opts}
		"""
	}

	echo "Archiving CML logs"
	archiveArtifacts artifacts: 'out-**/cml_logs/**, cml_logs/**', fingerprint: true, allowEmptyArchive: true
}

@Field def integrationTestMap = ["genericx86-64": this.&integrationTestX86];

def call(Map target) {
	// params
	// workspace: Jenkins workspace to operate on
	// gyroid_arch: GyroidOS architecture, used to determine manifest
	// gyroid_machine: GyroidOS machine type, used to determine manifest
	// buildtype: Type of image to build
	// selector: Build selector for CopyArtifact step
	// schsm_serial: serial of test schsm
	// schsm_pin: Pin of test schsm

	echo "Running on host: ${NODE_NAME}"

	echo "Entering stepIntegrationTest with parameters:\n\tworkspace: ${target.workspace}\n\tgyroid_arch: ${target.gyroid_arch}\n\tgyroid_machine: ${target.gyroid_machine}\n\tbuildtype: ${target.buildtype}\n\tselector: ${buildParameter('BUILDSELECTOR')}\n\tschsm_serial: ${target.schsm_serial}\n\tschsm_pin: ${target.schsm_pin}\n\t"

	script {
		def testFunc = integrationTestMap[target.gyroid_machine];
		if (testFunc != null) {
			testFunc(target);
		} else {
			echo "No integration test defined for machine ${target.gyroid_machine}. Skip."
			echo "${target.stage_name}"
			Utils.markStageSkippedForConditional(target.stage_name);
		}
	}
}
