pipeline {
	agent any

	options {
		preserveStashes(buildCount: 1) 
	}

	parameters {
		string(name: 'YOCTO_VERSION', defaultValue: 'kirkstone', description: 'Yocto version to build for, needed to trigger correct pipeline version in gyroidos/gyroidos repository')
		string(name: 'PR_BRANCHES', defaultValue: '', description: 'Comma separated list of additional pull request branches (e.g. meta-trustx=PR-177,meta-trustx-nxp=PR-13,gyroidos_build=PR-97)')
	}

	stages {
		stage('build GyroidOS') {
			steps {
				script {
					REPO_NAME = determineRepoName()

					sh 'env'

					if (env.CHANGE_TARGET != null) {
						// in case this is a PR build
						// set the BASE_BRANCH to the target
						// e.g. PR-123 -> kirkstone
						CI_LIB_VERSION = "pull/${CHANGE_ID}/head"
						echo "PR build, CI_LIB_VERSION is ${CI_LIB_VERSION}"
					} else {
						// in case this is a regular build
						// let the BASE_BRANCH equal this branch
						// e.g. kirkstone -> kirkstone
						CI_LIB_VERSION = env.BRANCH_NAME
						echo "Regular build, CI_LIB_VERSION is ${CI_LIB_VERSION}"
					}
				}

				build job: "../gyroidos/PR-42", wait: true, parameters: [
					string(name: "CI_LIB_VERSION", value: CI_LIB_VERSION),
					string(name: "PR_BRANCHES", value: PR_BRANCHES),
				]
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
