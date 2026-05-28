#!/usr/bin/env groovy

// Multi-Environment CI/CD Pipeline with Jenkins
// Author: DevOps Team
// Version: 2.0

pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
spec:
  serviceAccountName: jenkins-agent
  containers:
    - name: docker
      image: docker:24-dind
      securityContext:
        privileged: true
      volumeMounts:
        - name: docker-socket
          mountPath: /var/run/docker.sock
    - name: tools
      image: alpine/helm:3.13.0
      command: ['cat']
      tty: true
      resources:
        requests:
          cpu: 500m
          memory: 512Mi
    - name: python
      image: python:3.12-slim
      command: ['cat']
      tty: true
  volumes:
    - name: docker-socket
      hostPath:
        path: /var/run/docker.sock
"""
        }
    }

    options {
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))
        timestamps()
        ansiColor('xterm')
    }

    environment {
        APP_NAME        = 'myapp'
        REGISTRY        = 'registry.company.com'
        IMAGE_NAME      = "${REGISTRY}/${APP_NAME}"
        IMAGE_TAG       = "${env.GIT_COMMIT[0..7]}"
        KUBECONFIG_CRED = credentials('kubeconfig-prod')
        DOCKER_CRED     = credentials('docker-registry')
        SONAR_TOKEN     = credentials('sonarqube-token')
        SLACK_WEBHOOK   = credentials('slack-webhook')
    }

    parameters {
        choice(name: 'TARGET_ENV', choices: ['dev', 'staging', 'prod'], description: 'Target deployment environment')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip test execution')
        booleanParam(name: 'FORCE_DEPLOY', defaultValue: false, description: 'Force deploy even if tests fail')
        string(name: 'IMAGE_OVERRIDE', defaultValue: '', description: 'Override image tag (leave empty to use commit SHA)')
    }

    stages {
        // ──────────────────────────────────────────
        stage('Checkout & Setup') {
        // ──────────────────────────────────────────
            steps {
                script {
                    env.EFFECTIVE_TAG = params.IMAGE_OVERRIDE ?: env.IMAGE_TAG
                    env.FULL_IMAGE    = "${env.IMAGE_NAME}:${env.EFFECTIVE_TAG}"
                    
                    currentBuild.displayName = "#${BUILD_NUMBER} | ${env.GIT_BRANCH} | ${env.EFFECTIVE_TAG}"
                    currentBuild.description = "Deploying to: ${params.TARGET_ENV}"
                    
                    echo """
╔══════════════════════════════════════════╗
║         PIPELINE INITIALIZED             ║
╠══════════════════════════════════════════╣
║ Branch:      ${env.GIT_BRANCH}
║ Commit:      ${env.EFFECTIVE_TAG}
║ Image:       ${env.FULL_IMAGE}
║ Environment: ${params.TARGET_ENV}
╚══════════════════════════════════════════╝
                    """
                }
            }
        }

        // ──────────────────────────────────────────
        stage('Test') {
        // ──────────────────────────────────────────
            when {
                expression { !params.SKIP_TESTS }
            }
            parallel {
                stage('Unit Tests') {
                    steps {
                        container('python') {
                            sh '''
                                pip install -r app/requirements.txt pytest pytest-cov --quiet
                                pytest app/tests/unit/ \
                                    --cov=app/src \
                                    --cov-report=xml:coverage.xml \
                                    --cov-report=html:coverage-html \
                                    --junitxml=test-results.xml \
                                    -v
                            '''
                        }
                    }
                    post {
                        always {
                            junit 'test-results.xml'
                            publishCoverage adapters: [coberturaAdapter('coverage.xml')], sourceFileResolver: sourceFiles('STORE_LAST_BUILD')
                        }
                    }
                }
                
                stage('Integration Tests') {
                    steps {
                        container('python') {
                            sh '''
                                pip install -r app/requirements.txt pytest httpx --quiet
                                pytest app/tests/integration/ -v --timeout=30 || true
                            '''
                        }
                    }
                }
                
                stage('Code Quality - SonarQube') {
                    steps {
                        withSonarQubeEnv('sonarqube') {
                            sh """
                                sonar-scanner \
                                    -Dsonar.projectKey=${APP_NAME} \
                                    -Dsonar.sources=app/src \
                                    -Dsonar.tests=app/tests \
                                    -Dsonar.python.coverage.reportPaths=coverage.xml \
                                    -Dsonar.python.xunit.reportPath=test-results.xml \
                                    -Dsonar.qualitygate.wait=true
                            """
                        }
                        timeout(time: 5, unit: 'MINUTES') {
                            waitForQualityGate abortPipeline: !params.FORCE_DEPLOY
                        }
                    }
                }
            }
        }

        // ──────────────────────────────────────────
        stage('Security Scan') {
        // ──────────────────────────────────────────
            steps {
                container('docker') {
                    sh """
                        # Trivy filesystem scan
                        trivy fs --exit-code 0 --severity HIGH,CRITICAL \
                            --format json --output trivy-fs.json . || true
                        
                        # Detect-secrets
                        pip install detect-secrets --quiet
                        detect-secrets scan --baseline .secrets.baseline . || true
                    """
                }
            }
        }

        // ──────────────────────────────────────────
        stage('Build & Push Image') {
        // ──────────────────────────────────────────
            steps {
                container('docker') {
                    sh """
                        echo "${DOCKER_CRED_PSW}" | docker login ${REGISTRY} -u "${DOCKER_CRED_USR}" --password-stdin
                        
                        docker build \
                            --build-arg APP_VERSION=${EFFECTIVE_TAG} \
                            --build-arg BUILD_DATE=\$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                            --build-arg VCS_REF=${GIT_COMMIT} \
                            --label "org.opencontainers.image.revision=${GIT_COMMIT}" \
                            --label "org.opencontainers.image.created=\$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
                            --cache-from ${FULL_IMAGE} \
                            -t ${FULL_IMAGE} \
                            -f app/Dockerfile \
                            app/
                        
                        # Scan built image
                        trivy image --exit-code 1 --severity CRITICAL ${FULL_IMAGE} || \
                            (echo "CRITICAL vulnerabilities found!" && exit 1)
                        
                        docker push ${FULL_IMAGE}
                        
                        # Also tag with branch name
                        docker tag ${FULL_IMAGE} ${IMAGE_NAME}:${GIT_BRANCH.replaceAll('/', '-')}
                        docker push ${IMAGE_NAME}:${GIT_BRANCH.replaceAll('/', '-')}
                    """
                }
            }
        }

        // ──────────────────────────────────────────
        stage('Deploy to DEV') {
        // ──────────────────────────────────────────
            when {
                anyOf {
                    branch 'develop'
                    expression { params.TARGET_ENV == 'dev' }
                }
            }
            steps {
                container('tools') {
                    sh """
                        export KUBECONFIG=${KUBECONFIG_CRED}
                        
                        helm upgrade --install ${APP_NAME}-dev ./helm \
                            --namespace dev \
                            --create-namespace \
                            -f k8s/dev/values.yaml \
                            --set image.tag=${EFFECTIVE_TAG} \
                            --set environment=dev \
                            --atomic \
                            --timeout 5m \
                            --wait
                        
                        # Verify deployment
                        kubectl rollout status deployment/${APP_NAME}-dev -n dev --timeout=300s
                        
                        # Smoke test
                        kubectl run smoke-test-\${BUILD_NUMBER} \
                            --image=curlimages/curl:8.0 \
                            --restart=Never \
                            --namespace=dev \
                            -it --rm \
                            -- curl -f http://${APP_NAME}-dev/health
                    """
                }
            }
        }

        // ──────────────────────────────────────────
        stage('Deploy to STAGING') {
        // ──────────────────────────────────────────
            when {
                anyOf {
                    branch 'main'
                    expression { params.TARGET_ENV == 'staging' }
                }
            }
            steps {
                // Canary deployment
                container('tools') {
                    sh """
                        export KUBECONFIG=${KUBECONFIG_CRED}
                        
                        # Step 1: Deploy canary (10% traffic)
                        echo ">>> Deploying canary (10% traffic)..."
                        helm upgrade --install ${APP_NAME}-canary ./helm \
                            --namespace staging \
                            -f k8s/staging/values.yaml \
                            --set image.tag=${EFFECTIVE_TAG} \
                            --set replicaCount=1 \
                            --set canary.enabled=true \
                            --set canary.weight=10 \
                            --atomic --timeout 5m
                        
                        # Step 2: Monitor for 5 minutes
                        echo ">>> Monitoring canary for 5 minutes..."
                        sleep 300
                        
                        # Step 3: Check error rate
                        ERROR_RATE=\$(kubectl exec -n monitoring prometheus-0 -- \
                            promtool query instant 'rate(http_requests_total{status_code=~"5..",deployment="${APP_NAME}-canary"}[5m])' | \
                            grep -o '[0-9.]*' | head -1)
                        
                        if (( \$(echo "\$ERROR_RATE > 0.01" | bc -l) )); then
                            echo "ERROR: Canary error rate too high: \$ERROR_RATE"
                            helm rollback ${APP_NAME}-canary -n staging
                            exit 1
                        fi
                        
                        # Step 4: Full rollout
                        echo ">>> Canary healthy, promoting to full rollout..."
                        helm upgrade ${APP_NAME}-staging ./helm \
                            --namespace staging \
                            -f k8s/staging/values.yaml \
                            --set image.tag=${EFFECTIVE_TAG} \
                            --atomic --timeout 10m
                    """
                }
            }
        }

        // ──────────────────────────────────────────
        stage('Production Gate') {
        // ──────────────────────────────────────────
            when {
                expression { params.TARGET_ENV == 'prod' }
            }
            steps {
                timeout(time: 24, unit: 'HOURS') {
                    input message: """
🚀 PRODUCTION DEPLOYMENT APPROVAL REQUIRED

App:     ${APP_NAME}
Image:   ${EFFECTIVE_TAG}  
Branch:  ${GIT_BRANCH}

Please verify:
✅ Staging tests passed
✅ Security scan clean
✅ Change request approved
✅ On-call team notified

Approver: """,
                    submitter: 'devops-leads,release-managers',
                    ok: 'APPROVE PRODUCTION DEPLOYMENT'
                }
            }
        }

        // ──────────────────────────────────────────
        stage('Deploy to PRODUCTION') {
        // ──────────────────────────────────────────
            when {
                expression { params.TARGET_ENV == 'prod' }
            }
            steps {
                container('tools') {
                    sh """
                        export KUBECONFIG=${KUBECONFIG_CRED}
                        
                        # Blue-green deployment
                        CURRENT_COLOR=\$(kubectl get service ${APP_NAME} -n prod \
                            -o jsonpath='{.spec.selector.color}' 2>/dev/null || echo "blue")
                        NEW_COLOR=\$([ "\$CURRENT_COLOR" = "blue" ] && echo "green" || echo "blue")
                        
                        echo ">>> Blue-Green: Current=\$CURRENT_COLOR, Deploying to=\$NEW_COLOR"
                        
                        # Deploy to new color
                        helm upgrade --install ${APP_NAME}-\$NEW_COLOR ./helm \
                            --namespace prod \
                            -f k8s/prod/values.yaml \
                            --set image.tag=${EFFECTIVE_TAG} \
                            --set color=\$NEW_COLOR \
                            --set replicaCount=5 \
                            --atomic --timeout 10m
                        
                        # Verify new deployment
                        kubectl rollout status deployment/${APP_NAME}-\$NEW_COLOR -n prod --timeout=600s
                        
                        # Switch traffic
                        kubectl patch service ${APP_NAME} -n prod \
                            -p "{\\"spec\\":{\\"selector\\":{\\"color\\":\\"\$NEW_COLOR\\"}}}"
                        
                        echo ">>> Traffic switched to \$NEW_COLOR. Old \$CURRENT_COLOR deployment kept for rollback."
                        echo ">>> To rollback: kubectl patch service ${APP_NAME} -n prod -p '{\\"spec\\":{\\"selector\\":{\\"color\\":\\"\$CURRENT_COLOR\\"}}}''"
                    """
                }
            }
        }
    }

    post {
        always {
            script {
                def status  = currentBuild.currentResult
                def emoji   = status == 'SUCCESS' ? '✅' : status == 'FAILURE' ? '❌' : '⚠️'
                def color   = status == 'SUCCESS' ? 'good' : status == 'FAILURE' ? 'danger' : 'warning'
                def msg = "${emoji} *${APP_NAME}* | Build #${BUILD_NUMBER} | ${status}\n" +
                          "Branch: `${GIT_BRANCH}` | Tag: `${EFFECTIVE_TAG}` | Env: `${params.TARGET_ENV}`\n" +
                          "Duration: ${currentBuild.durationString}\n" +
                          "<${BUILD_URL}|View Build>"
                
                sh "curl -s -X POST '${SLACK_WEBHOOK}' -H 'Content-type: application/json' " +
                   "-d '{\"attachments\":[{\"color\":\"${color}\",\"text\":\"${msg.replace('"', '\\"')}\"}]}'"
            }
        }
        
        success {
            archiveArtifacts artifacts: 'trivy-*.json,coverage.xml', allowEmptyArchive: true
        }
        
        failure {
            emailext(
                subject: "FAILED: ${APP_NAME} Pipeline #${BUILD_NUMBER}",
                body: "${BUILD_URL}",
                to: "devops-team@company.com"
            )
        }
    }
}
