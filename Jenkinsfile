def project = 'omisego'
def appName = 'ewallet'
def imageName = "${project}/${appName}"

def appImage
def releaseVersion
def builderImageName = 'omisegoimages/ewallet-builder:beec6e8'
def acceptanceImageName = 'python:3.6-alpine'
def acceptanceMailerImageName = 'mailhog/mailhog:v1.0.0'

def label = "ewallet-${UUID.randomUUID().toString()}"
def buildMsg
def gitCommit
def gitMergeBase

def yamlSpec = """
spec:
  nodeSelector:
    cloud.google.com/gke-preemptible: "true"
  tolerations:
    - key: dedicated
      operator: Equal
      value: worker
      effect: NoSchedule
"""

def prontoNotifyType = 'github'
if (env.CHANGE_ID) {
    prontoNotifyType = 'github_pr_review'
}

podTemplate(
    label: label,
    yaml: yamlSpec,
    containers: [
        containerTemplate(
            name: 'jnlp',
            image: 'omisegoimages/jenkins-slave:3.19-alpine',
            args: '${computer.jnlpmac} ${computer.name}',
            resourceRequestCpu: '200m',
            resourceLimitCpu: '500m',
            resourceRequestMemory: '256Mi',
            resourceLimitMemory: '1024Mi',
            envVars: [
                containerEnvVar(key: 'DOCKER_HOST', value: 'tcp://localhost:2375')
            ]
        ),
        containerTemplate(
            name: 'dind',
            image: 'docker:18.05-dind',
            privileged: true,
            resourceRequestCpu: '700m',
            resourceLimitCpu: '1500m',
            resourceRequestMemory: '1024Mi',
            resourceLimitMemory: '2048Mi',
        ),
    ],
) {
    try {
        notifySlack('STARTED', null)

        node(label) {
            def nodeIP = getNodeIP()
            def tmpDir = pwd(tmp: true)

            /* ------------------------------------------------------------------------
             * Stage: Checkout
             * ------------------------------------------------------------------------ */

            try {
                stage('Checkout') {
                    checkout([
                        $class: 'GitSCM',
                        branches: scm.branches,
                        doGenerateSubmoduleConfigurations: scm.doGenerateSubmoduleConfigurations,
                        userRemoteConfigs: scm.userRemoteConfigs,
                        extensions: [[
                            $class: 'CloneOption',
                            depth: 0,
                            noTags: true,
                            reference: '',
                            shallow: false
                        ]],
                    ])

                    gitCommit = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    gitMergeBase = sh(script: "git merge-base remotes/origin/develop ${gitCommit}", returnStdout: true).trim()
                    releaseVersion = sh(
                        script: "cat apps/ewallet/mix.exs |grep -i version |tr -d '[:blank:]' |cut -d\"\\\"\" -f2",
                        returnStdout: true
                    ).trim()
                }
            } catch(e) {
                currentBuild.result = "FAILURE"
                buildMsg = "Build failed during checkout"
                throw e
            }

            cache(maxCacheSize: 250, caches: [
                [$class: 'ArbitraryFileCache', excludes: '', includes: '**/*', path: '_build'],
                [$class: 'ArbitraryFileCache', excludes: '', includes: '**/*', path: 'deps'],
            ]) {

                docker.image('postgres:9.6.9-alpine').withRun('-p 5432:5432') { c ->
                    docker.image(builderImageName).inside() {

                        /* ------------------------------------------------------------------------
                         * Stage: Dependencies retrieval
                         * ------------------------------------------------------------------------ */

                        try {
                            stage('Deps') {
                                retry(3) {
                                    sh("make deps")
                                }
                            }
                        } catch (e) {
                            currentBuild.result = "FAILURE"
                            buildMsg = "Build failed during dependencies retrieval"
                            throw e
                        }

                        /* ------------------------------------------------------------------------
                         * Stage: Lint
                         * ------------------------------------------------------------------------ */

                        try {
                            stage('Test') {
                                sh("make build-test")

                                withEnv(['MIX_ENV=test']) {
                                    parallel(
                                        lint: {
                                            withCredentials([
                                                usernamePassword(
                                                    credentialsId: '90e46674-4a3b-4894-b33f-41fe6549ac6f',
                                                    passwordVariable: 'PRONTO_GITHUB_ACCESS_TOKEN',
                                                    usernameVariable: ''
                                                )
                                            ]) {
                                                withEnv([
                                                    'PRONTO_VERBOSE=true',
                                                    "PRONTO_PULL_REQUEST=${env.CHANGE_ID}",
                                                ]) {
                                                    sh('mix dialyzer -- --format dialyzer | grep -E \'\\.exs?:[0-9]+\' > dialyzer.out')
                                                    sh("pronto run -f ${prontoNotifyType} -c ${gitMergeBase}")
                                                    sh("rm dialyzer.out")
                                                }
                                            }
                                        },
                                        test: {
                                            withEnv([
                                                'USE_JUNIT=1',
                                                "DATABASE_URL=postgresql://postgres@${nodeIP}:5432/ewallet_${gitCommit}_ewallet",
                                                "LOCAL_LEDGER_DATABASE_URL=postgresql://postgres@${nodeIP}:5432/ewallet_${gitCommit}_local_ledger",
                                            ]) {
                                                sh("make test")
                                            }
                                        }
                                    )
                                }
                            }
                        } catch(e) {
                            currentBuild.result = "FAILURE"
                            buildMsg = "Build failed during test stage"
                            throw e
                        } finally {
                            junit('_build/test/**/test-junit-report.xml')
                        }

                    }
                }

                /* ------------------------------------------------------------------------
                 * Stage: Build, Acceptance, Publish, Deploy
                 * Only run on master branch.
                 * ------------------------------------------------------------------------ */

                /* TODO: switch to master/develop */
                if (env.BRANCH_NAME == 'distillery-release') {

                    /* ------------------------------------------------------------------------
                     * Stage: Build
                     * ------------------------------------------------------------------------ */

                    /* TODO: use a pre-start hook to generate JSON spec.
                     * See https://github.com/omisego/ewallet/pull/228#issuecomment-397555334
                     */
                    try {
                        stage('Build') {
                            docker.image(builderImageName).inside() {
                                sh("make build-prod")
                            }

                            sh("cp _build/prod/rel/ewallet/releases/${releaseVersion}/ewallet.tar.gz .")
                            dockerImage = docker.build("${imageName}:${gitCommit}")
                        }
                    } catch(e) {
                        currentBuild.result = "FAILURE"
                        buildMsg = "Build failed during build stage"
                        throw e
                    }

                    /* ------------------------------------------------------------------------
                     * Stage: Acceptance testing
                     * ------------------------------------------------------------------------ */

                    try {
                        stage('Acceptance') {
                            dir("${tmpDir}/acceptance") {
                                checkout([
                                    $class: 'GitSCM',
                                    branches: [[name: '*/development']],
                                    userRemoteConfigs: [
                                        [
                                            url: 'ssh://git@github.com/omisego/e2e.git',
                                            credentialsId: 'github',
                                        ],
                                    ]
                                ])

                                /* TODO: We should probably randomize password and stuff and also drop PostgreSQL privileges. */
                                docker.image('postgres:9.6.9-alpine').withRun('-e POSTGRESQL_PASSWORD=passw9rd') { c ->
                                    def runArgs = """
                                        --link ${c.id}:db
                                        -e DATABASE_URL=postgresql://postgres:passw9rd@db:5432/ewallet_e2e
                                        -e LOCAL_LEDGER_DATABASE_URL=postgresql://postgres:passw9rd@db:5432/local_ledger_e2e
                                        -e EWALLET_SECRET_KEY="wd44H8d3YarZUHvw7+2z5cu90ulahUTTkA9Wz55yLBs="
                                        -e LOCAL_LEDGER_SECRET_KEY="2Qd2KmR4nENrAAh8FMpfW5FhBcav/gvoenah77q2Avk="
                                    """.split().join(" ")

                                    def e2eArgs = [
                                        'E2E_TEST_ADMIN_EMAIL=john@example.com',
                                        'E2E_TEST_ADMIN_PASSWORD=passw0rd',
                                        'E2E_TEST_ADMIN_1_EMAIL=smith@example.com',
                                        'E2E_TEST_ADMIN_1_PASSWORD=passw1rd',
                                        'E2E_HTTP_HOST=http://ewallet:4000',
                                        'E2E_SOCKET_HOST=ws://ewallet:4000',
                                        'SMTP_HOST=mailhog',
                                        'SMTP_PORT=1025',
                                    ]

                                    dockerImage.inside(runArgs) {
                                        withEnv(e2eArgs) {
                                            sh('/app/bin/ewallet initdb')
                                            sh('/app/bin/ewallet seed --e2e')
                                        }
                                    }

                                    dockerImage.withRun(runArgs) { ci ->
                                        docker.image(acceptanceMailerImageName) { cm ->
                                            docker.image(acceptanceImageName).inside("--link ${ci.id}:ewallet --link ${cm.id}:mailhog") {
                                                withEnv(e2eArgs + e2eMailerArgs) {
                                                    sh('apk add --update --no-cache make')
                                                    sh('make setup test')
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } catch(e) {
                        currentBuild.result = "FAILURE"
                        buildMsg = "Build failed during acceptance testing"
                        throw e
                    }

                    /* ------------------------------------------------------------------------
                     * Stage: Publish
                     * ------------------------------------------------------------------------ */

                    try {
                        stage('Publish') {
                            withDockerRegistry(credentialsId: 'd56e0a36-71d1-4c1b-a2c1-d8763f28d7f2') {
                                dockerImage.push()
                            }
                        }
                    } catch(e) {
                        currentBuild.result = "WARN"
                        buildMsg = "Could not publish the release"
                    }

                    /* ------------------------------------------------------------------------
                     * Stage: Deploy
                     * ------------------------------------------------------------------------ */

                    /* TODO: actually deploying. */
                    if (currentBuild.result == null || currentBuild.result == 'SUCCESS') {
                        try {
                            stage('Deploy') {
                            }
                        } catch(e) {
                            currentBuild.result = "WARN"
                            buildMsg = "The release could not be deployed"
                        }
                    }

                }
            }
        }
    } finally {
        notifySlack(currentBuild.result, buildMsg)
    }
}

def getNodeIP() {
    def rawNodeIP = sh(script: 'ip -4 -o addr show scope global', returnStdout: true).trim()
    def matched = (rawNodeIP =~ /inet (\d+\.\d+\.\d+\.\d+)/)
    return "" + matched[0].getAt(1)
}

def getPodID(String opts) {
    def pods = sh(script: "kubectl get pods ${opts} -o name", returnStdout: true).trim()
    def matched = (pods.split()[0] =~ /pods\/(.+)/)
    return "" + matched[0].getAt(1)
}

def notifySlack(String buildStatus = 'STARTED', String buildMsg) {
    def statusColor
    def statusName
    def statusMsg

    buildStatus = buildStatus ?: 'SUCCESSFUL'

    switch (buildStatus) {
        case 'STARTED':
            statusColor = "#3377aa"
            statusName = 'Started:'
            break
        case 'SUCCESSFUL':
            statusColor = '#77aa33'
            statusName = 'Success:'
            break
        case 'WARN':
            statusColor = '#eeaa22'
            statusName = 'Warning:'
            break
        default:
            statusColor = '#dd4455'
            statusName = 'Failure:'
            break
    }

    statusMsg = "${statusName} <${env.RUN_DISPLAY_URL}|${env.JOB_NAME} #${env.BUILD_NUMBER}>\n"
    if (buildMsg != null) {
        statusMsg = "${statusMsg}\n${buildMsg}"
    }

    slackSend(
        channel: "#sandbox",
        color: statusColor,
        message: statusMsg
    )
}
