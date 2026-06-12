// ============================================================
//  StreamingApp — Jenkins CI/CD Pipeline
//  Builds Docker images, pushes to ECR, deploys to EKS via Helm
// ============================================================
pipeline {

    agent any

    // ── Tool versions ────────────────────────────────────────
    environment {
        // AWS / ECR
        AWS_REGION        = 'ap-south-1'
        AWS_ACCOUNT_ID    = credentials('aws-account-id')      // Jenkins Secret Text
        ECR_REGISTRY      = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECR_REPO_FRONTEND = 'streaming-app/frontend'
        ECR_REPO_BACKEND  = 'streaming-app/backend'

        // Image tagging
        IMAGE_TAG         = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"

        // EKS
        EKS_CLUSTER_NAME  = 'streaming-eks-cluster'
        HELM_RELEASE      = 'streaming-app'
        K8S_NAMESPACE     = 'streaming'

        // Credentials IDs configured in Jenkins
        AWS_CREDENTIALS   = 'aws-ecr-credentials'
        KUBECONFIG_CRED   = 'eks-kubeconfig'
    }

    // ── Trigger: poll SCM every minute ───────────────────────
    triggers {
        pollSCM('* * * * *')
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 45, unit: 'MINUTES')
        timestamps()
    }

    stages {

        // ────────────────────────────────────────────────────
        stage('Checkout') {
        // ────────────────────────────────────────────────────
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_MSG = sh(
                        script: 'git log -1 --pretty=%B',
                        returnStdout: true
                    ).trim()
                    echo "Building commit: ${env.GIT_COMMIT_MSG}"
                }
            }
        }

        // ────────────────────────────────────────────────────
        stage('Lint & Unit Tests') {
        // ────────────────────────────────────────────────────
            parallel {
                stage('Frontend Tests') {
                    steps {
                        dir('frontend') {
                            sh '''
                                npm ci --silent
                                npm run lint   --if-present
                                npm test -- --watchAll=false --ci --passWithNoTests
                            '''
                        }
                    }
                }
                stage('Backend Tests') {
                    steps {
                        dir('backend') {
                            sh '''
                                npm ci --silent
                                npm run lint   --if-present
                                npm test -- --ci --passWithNoTests
                            '''
                        }
                    }
                }
            }
        }

        // ────────────────────────────────────────────────────
        stage('ECR Login') {
        // ────────────────────────────────────────────────────
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${AWS_CREDENTIALS}",
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {
                    sh '''
                        aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin ${ECR_REGISTRY}
                    '''
                }
            }
        }

        // ────────────────────────────────────────────────────
        stage('Build Docker Images') {
        // ────────────────────────────────────────────────────
            parallel {
                stage('Build Frontend') {
                    steps {
                        sh '''
                            docker build \
                              --tag ${ECR_REGISTRY}/${ECR_REPO_FRONTEND}:${IMAGE_TAG} \
                              --tag ${ECR_REGISTRY}/${ECR_REPO_FRONTEND}:latest \
                              --file frontend/Dockerfile \
                              ./frontend
                        '''
                    }
                }
                stage('Build Backend') {
                    steps {
                        sh '''
                            docker build \
                              --tag ${ECR_REGISTRY}/${ECR_REPO_BACKEND}:${IMAGE_TAG} \
                              --tag ${ECR_REGISTRY}/${ECR_REPO_BACKEND}:latest \
                              --file backend/Dockerfile \
                              ./backend
                        '''
                    }
                }
            }
        }

        // ────────────────────────────────────────────────────
        stage('Push to ECR') {
        // ────────────────────────────────────────────────────
            parallel {
                stage('Push Frontend') {
                    steps {
                        sh '''
                            docker push ${ECR_REGISTRY}/${ECR_REPO_FRONTEND}:${IMAGE_TAG}
                            docker push ${ECR_REGISTRY}/${ECR_REPO_FRONTEND}:latest
                        '''
                    }
                }
                stage('Push Backend') {
                    steps {
                        sh '''
                            docker push ${ECR_REGISTRY}/${ECR_REPO_BACKEND}:${IMAGE_TAG}
                            docker push ${ECR_REGISTRY}/${ECR_REPO_BACKEND}:latest
                        '''
                    }
                }
            }
        }

        // ────────────────────────────────────────────────────
        stage('Update EKS Kubeconfig') {
        // ────────────────────────────────────────────────────
            steps {
                withCredentials([file(credentialsId: "${KUBECONFIG_CRED}", variable: 'KUBECONFIG')]) {
                    sh '''
                        aws eks update-kubeconfig \
                          --region ${AWS_REGION} \
                          --name   ${EKS_CLUSTER_NAME}
                        kubectl get nodes
                    '''
                }
            }
        }

        // ────────────────────────────────────────────────────
        stage('Helm Deploy') {
        // ────────────────────────────────────────────────────
            steps {
                withCredentials([file(credentialsId: "${KUBECONFIG_CRED}", variable: 'KUBECONFIG')]) {
                    sh '''
                        # Create namespace if not exists
                        kubectl create namespace ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

                        # Deploy / upgrade release
                        helm upgrade --install ${HELM_RELEASE} ./helm/streaming-app \
                          --namespace ${K8S_NAMESPACE} \
                          --set frontend.image.repository=${ECR_REGISTRY}/${ECR_REPO_FRONTEND} \
                          --set frontend.image.tag=${IMAGE_TAG} \
                          --set backend.image.repository=${ECR_REGISTRY}/${ECR_REPO_BACKEND} \
                          --set backend.image.tag=${IMAGE_TAG} \
                          --set mongodb.uri=${MONGODB_URI} \
                          --wait \
                          --timeout 5m0s

                        # Confirm rollout
                        kubectl rollout status deployment/streaming-frontend -n ${K8S_NAMESPACE}
                        kubectl rollout status deployment/streaming-backend  -n ${K8S_NAMESPACE}
                    '''
                }
            }
        }

        // ────────────────────────────────────────────────────
        stage('Smoke Test') {
        // ────────────────────────────────────────────────────
            steps {
                withCredentials([file(credentialsId: "${KUBECONFIG_CRED}", variable: 'KUBECONFIG')]) {
                    sh '''
                        FRONTEND_URL=$(kubectl get svc streaming-frontend-svc \
                          -n ${K8S_NAMESPACE} \
                          -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
                        echo "Frontend URL: http://${FRONTEND_URL}"
                        curl --fail --retry 5 --retry-delay 10 http://${FRONTEND_URL}/health
                    '''
                }
            }
        }

    } // end stages

    // ── Post actions ─────────────────────────────────────────
    post {

        always {
            // Clean local Docker images to free disk space
            sh '''
                docker rmi ${ECR_REGISTRY}/${ECR_REPO_FRONTEND}:${IMAGE_TAG} || true
                docker rmi ${ECR_REGISTRY}/${ECR_REPO_BACKEND}:${IMAGE_TAG}  || true
            '''
        }

        success {
            echo "✅ Build #${env.BUILD_NUMBER} deployed successfully — tag: ${IMAGE_TAG}"
            // SNS notification (Bonus Step 9)
            sh '''
                aws sns publish \
                  --region      ${AWS_REGION} \
                  --topic-arn   ${SNS_TOPIC_ARN} \
                  --subject     "✅ StreamingApp Deploy SUCCESS — Build #${BUILD_NUMBER}" \
                  --message     "Branch: ${GIT_BRANCH}\nCommit: ${GIT_COMMIT}\nImage Tag: ${IMAGE_TAG}\nJenkins URL: ${BUILD_URL}" \
                  || true
            '''
        }

        failure {
            echo "❌ Build #${env.BUILD_NUMBER} FAILED"
            sh '''
                aws sns publish \
                  --region      ${AWS_REGION} \
                  --topic-arn   ${SNS_TOPIC_ARN} \
                  --subject     "❌ StreamingApp Deploy FAILED  — Build #${BUILD_NUMBER}" \
                  --message     "Branch: ${GIT_BRANCH}\nCommit: ${GIT_COMMIT}\nCheck logs: ${BUILD_URL}console" \
                  || true
            '''
        }

    }

} // end pipeline
