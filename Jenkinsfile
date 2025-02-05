pipeline {
	agent any

	options {
		preserveStashes(buildCount: 1) 
	}

	parameters {
		string(name: 'YOCTO_VERSION', defaultValue: 'kirkstone', description: 'Yocto version to build for, needed to trigger correct pipeline version in gyroidos/gyroidos repository')
		string(name: 'PR_BRANCHES', defaultValue: '', description: 'Comma separated list of additional pull request branches (e.g. meta-gyroidos=PR-177,meta-gyroidos-nxp=PR-13,gyroidos_build=PR-97)')
		string(name: 'DOWNSTREAM_BUILD', defaultValue: '', description: 'Downstream build number to rebuild')
		string(name: 'PIPELINE_BRANCH', defaultValue: '${YOCTO_VERSION}', description: 'Branch of main pipeline (gyroidos/gyroidos) to build, e.g. \'PR-<number>\' to build PR')
		booleanParam(name: 'SKIP_WS_CLEANUP', defaultValue: false, description: 'If true, workspace cleanup after build will be skipped')
	}




	stages {
		stage('build GyroidOS') {
			parallel {
				stage('build x86') {
					steps {

						script {
							REPO_NAME = determineRepoName()
		
							sh 'env'
		
							CI_LIB_VERSION = determineCILibVersion()
		
							if (params.containsKey('DOWNSTREAM_BUILD') && "" != params.DOWNSTREAM_BUILD) {
								echo "Passing build number \'${params.DOWNSTREAM_BUILD}\' for CopyArtifacts in downstream pipeline"
								echo "CI_LIB_VERSION  build number \'${params.DOWNSTREAM_BUILD}\' for CopyArtifacts in downstream pipeline"
		
								build job: "../gyroidos/${PIPELINE_BRANCH}", wait: true, parameters: [
									string(name: "CI_LIB_VERSION", value: CI_LIB_VERSION),
									string(name: "GYROID_ARCH", value: "x86"),
									string(name: "GYROID_MACHINE", value: "genericx86-64"),
									string(name: "PR_BRANCHES", value: params.PR_BRANCHES),
									string(name: 'BUILDSELECTOR', value: "<SpecificBuildSelector plugin='copyartifact'>  <buildNumber>${DOWNSTREAM_BUILD}</buildNumber></SpecificBuildSelector>"),
									booleanParam(name: "SKIP_WS_CLEANUP", value: params.SKIP_WS_CLEANUP)
								]
							} else {
								echo "Not passing build number for CopyArtifacts in downstream pipeline"
		
								build job: "../gyroidos/${PIPELINE_BRANCH}", wait: true, parameters: [
									string(name: "CI_LIB_VERSION", value: CI_LIB_VERSION),
									string(name: "GYROID_ARCH", value: "x86"),
									string(name: "GYROID_MACHINE", value: "genericx86-64"),
									string(name: "PR_BRANCHES", value: params.PR_BRANCHES),
									booleanParam(name: "SKIP_WS_CLEANUP", value: params.SKIP_WS_CLEANUP)
								]
							}
						}
					}
				}

				stage('build arm64') {
					steps {

						script {
							REPO_NAME = determineRepoName()
		
							sh 'env'
		
							CI_LIB_VERSION = determineCILibVersion()
		
							if (params.containsKey('DOWNSTREAM_BUILD') && "" != params.DOWNSTREAM_BUILD) {
								echo "Passing build number \'${params.DOWNSTREAM_BUILD}\' for CopyArtifacts in downstream pipeline"
								echo "CI_LIB_VERSION  build number \'${params.DOWNSTREAM_BUILD}\' for CopyArtifacts in downstream pipeline"
		
								build job: "../gyroidos/${PIPELINE_BRANCH}", wait: true, parameters: [
									string(name: "CI_LIB_VERSION", value: CI_LIB_VERSION),
									string(name: "GYROID_ARCH", value: "arm64"),
									string(name: "GYROID_MACHINE", value: "tqma8mpxl"),
									string(name: "PR_BRANCHES", value: params.PR_BRANCHES),
									string(name: 'BUILDSELECTOR', value: "<SpecificBuildSelector plugin='copyartifact'>  <buildNumber>${DOWNSTREAM_BUILD}</buildNumber></SpecificBuildSelector>"),
									booleanParam(name: "SKIP_WS_CLEANUP", value: params.SKIP_WS_CLEANUP)
								]
							} else {
								echo "Not passing build number for CopyArtifacts in downstream pipeline"
		
								build job: "../gyroidos/${PIPELINE_BRANCH}", wait: true, parameters: [
									string(name: "GYROID_ARCH", value: "arm64"),
									string(name: "GYROID_MACHINE", value: "tqma8mpxl"),
									string(name: "CI_LIB_VERSION", value: CI_LIB_VERSION),
									string(name: "PR_BRANCHES", value: params.PR_BRANCHES),
									booleanParam(name: "SKIP_WS_CLEANUP", value: params.SKIP_WS_CLEANUP)
								]
							}
						}
					}










				}
			}
		}
	}
}

// Determine the Repository name from its URL.
// Avoids hardcoding the name in every Jenkinsfile individually.
// Source: https://stackoverflow.com/a/45690925
String determineRepoName() {
	return scm.getUserRemoteConfigs()[0].getUrl().tokenize('/').last().split("\\.")[0]
}

String determineBaseBranch() {
	if (env.CHANGE_TARGET != null) {
		// in case this is a PR build
		// set the BASE_BRANCH to the target
		// e.g. PR-123 -> kirkstone
		return env.CHANGE_TARGET
	} else {
		// in case this is a regular build
		// let the BASE_BRANCH equal this branch
		// e.g. kirkstone -> kirkstone
		return env.BRANCH_NAME
	}
}

String determineCILibVersion() {
	if (env.CHANGE_TARGET != null) {
		// in case this is a PR build
		// set the BASE_BRANCH to the target
		// e.g. PR-123 -> kirkstone
		echo "PR build, CI_LIB_VERSION is pull/${CHANGE_ID}/head"
		return "pull/${CHANGE_ID}/head"
	} else {
		// in case this is a regular build
		// let the BASE_BRANCH equal this branch
		// e.g. kirkstone -> kirkstone
		echo "Regular build, CI_LIB_VERSION is ${env.BRANCH_NAME}"
		return env.BRANCH_NAME
	}
}
