@Library('github.com/omisego/jenkins-pipeline-scripts') _

/* --------------------------------------------------------------------------
 * Docker target
 * -------------------------------------------------------------------------- */

def project = "omisego"
def appName = "ewallet"
def imageName = "${project}/${appName}"

/* --------------------------------------------------------------------------
 * Image setup
 * -------------------------------------------------------------------------- */

def builderImageName = "omisegoimages/ewallet-builder:beec6e8"
def mailerImageName = "mailhog/mailhog:v1.0.0"
def postgresImageName = "postgres:9.6.9-alpine"
def pythonImageName = "python:3.6-alpine"

/* --------------------------------------------------------------------------
 * Global variables
 * -------------------------------------------------------------------------- */

def appImage
def releaseVersion
def gitCommit
def gitMergeBase

/* --------------------------------------------------------------------------
 * Misc
 * -------------------------------------------------------------------------- */

def slackChannel = "#sandbox"

/* --------------------------------------------------------------------------
 * Hic sunt dracones
 * -------------------------------------------------------------------------- */

wrapKitchenSink(slackChannel: slackChannel) {
    def tmpDir = pwd(tmp: true)

    wrapStage(stageName: "Checkout", slackChannel: slackChannel) {
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

        gitCommit = getGitCommit()
        gitMergeBase = getGitMergeBase("remotes/origin/master", gitCommit)
        releaseVersion = getMixReleaseVersion("apps/ewallet/mix.exs")
    }

    wrapStage(stageName: "Test", stageJunit: "_build/test/**/test-junit-report.xml", slackChannel: slackChannel) {
        cache(maxCacheSize: 250, caches: [
            [$class: "ArbitraryFileCache", excludes: "", includes: "**/*", path: "_build"],
            [$class: "ArbitraryFileCache", excludes: "", includes: "**/*", path: "deps"],
        ]) {
            docker.image(postgresImageName).withRun("-e POSTGRESQL_PASSWORD=passw9rd") { pgContainer ->
                docker.image(builderImageName).inside(
                """
                    --link ${pgContainer.id}:pg
                    -e DATABASE_URL=postgresql://postgres:passw9rd@pg:5432/ewallet_${gitCommit}_ewallet
                    -e LOCAL_LEDGER_DATABASE_URL=postgresql://postgres:passw9rd@pg:5432/ewallet_${gitCommit}_local_ledger
                    -e MIX_ENV=test
                    -e PRONTO_PULL_REQUEST=${env.CHANGE_ID}
                    -e PRONTO_VERBOSE=true
                    -e USE_JUNIT=1
                """.split().join(" ")
                ) {
                    sh("make deps")
                    sh("make build-test")

                    def prontoNotifyType = "github"
                    if (env.CHANGE_ID) {
                        prontoNotifyType = "github_pr_review"
                    }

                    parallel(
                        lint: {
                            withCredentials([
                                usernamePassword(
                                    credentialsId: "90e46674-4a3b-4894-b33f-41fe6549ac6f",
                                    passwordVariable: "PRONTO_GITHUB_ACCESS_TOKEN",
                                    usernameVariable: ""
                                )
                            ]) {
                                sh("mix dialyzer -- --format dialyzer | grep -E \'\\.exs?:[0-9]+\' > dialyzer.out")
                                sh("pronto run -f ${prontoNotifyType} -c ${gitMergeBase}")
                                sh("rm dialyzer.out")
                            }
                        },
                        ewallet: {
                            retry(5) {
                                sh("make test-ewallet")
                            }
                        },
                        assets: {
                            sh("make test-assets")
                        }
                    )
                }
            }
        }
    }

    /* TODO: switch to master */
    if (true) {
        wrapStage(stageName: "Build", slackChannel: slackChannel) {
            docker.image(builderImageName).inside() {
                sh("make build-prod")
            }

            sh("cp _build/prod/rel/ewallet/releases/${releaseVersion}/ewallet.tar.gz .")
            appImage = docker.build("${imageName}:${gitCommit}")
        }

        wrapStage(stageName: "Acceptance", slackChannel: slackChannel) {
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

                /* TODO: We should randomize password and drop PostgreSQL privileges. */
                docker.image(postgresImageName).withRun("-e POSTGRESQL_PASSWORD=passw9rd") { pgContainer ->
                    docker.image(mailerImageName).withRun() { mailerContainer ->
                        def runArgs = """
                            --link ${pgContainer.id}:pg
                            --link ${mailerContainer.id}:mailhog
                            -e DATABASE_URL=postgresql://postgres:passw9rd@pg:5432/ewallet_e2e
                            -e LOCAL_LEDGER_DATABASE_URL=postgresql://postgres:passw9rd@pg:5432/local_ledger_e2e
                            -e EWALLET_SECRET_KEY="wd44H8d3YarZUHvw7+2z5cu90ulahUTTkA9Wz55yLBs="
                            -e LOCAL_LEDGER_SECRET_KEY="2Qd2KmR4nENrAAh8FMpfW5FhBcav/gvoenah77q2Avk="
                            -e SMTP_HOST=mailhog
                            -e SMTP_PORT=1025
                        """.split().join(" ")

                        def e2eRunArgs = """
                            -e E2E_TEST_ADMIN_EMAIL=john@example.com
                            -e E2E_TEST_ADMIN_PASSWORD=passw0rd
                            -e E2E_TEST_ADMIN_1_EMAIL=smith@example.com
                            -e E2E_TEST_ADMIN_1_PASSWORD=passw1rd
                            -e E2E_HTTP_HOST=http://ewallet:4000
                            -e E2E_SOCKET_HOST=ws://ewallet:4000
                        """.split().join(" ")

                        appImage.inside("${runArgs} --entrypoint /bin/sh") {
                            sh("/app/bin/ewallet initdb")
                            sh("/app/bin/ewallet seed --e2e")
                        }

                        appImage.withRun(runArgs) { ewalletContainer ->
                            docker.image(pythonImageName).inside("--link ${ewalletContainer.id}:ewallet ${e2eRunArgs}") {
                                sh("apk add --update --no-cache make")
                                sh("make setup test")
                            }
                        }
                    }
                }
            }
        }

        wrapStage(stageName: "Publish", slackChannel: slackChannel) {
            withDockerRegistry(credentialsId: "d56e0a36-71d1-4c1b-a2c1-d8763f28d7f2") {
                appImage.push()
            }
        }

        /* TODO: actually deploying. */
        wrapStage(stageName: "Deploy", slackChannel: slackChannel) {
        }
    }
}
