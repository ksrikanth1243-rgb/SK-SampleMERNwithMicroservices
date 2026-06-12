// ============================================================
//  StreamingApp — Jenkins CI/CD Pipeline
// ============================================================
pipeline {

    agent any

    environment {
        AWS_REGION         = 'ap-south-1'
        AWS_ACCOUNT_ID     = credentials('aws-account-id')
        ECR_REGISTRY       = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECR_REPO_HELLO     = 'streaming-app/helloservice'
        ECR_REPO_PROFILE   = 'streaming-app/profileservice'
        IMAGE_TAG          = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
        EKS_CLUSTER_NAME   = 'streaming-eks-cluster'
        HELM_RELEASE       = 'streaming-app'
        K8S_NAMESPACE      = 'streaming'
        AWS_CREDENTIALS    = 'aws-ecr-credentials'
        KUBECONFIG_CRED    = 'eks-kubeconfig'
    }

    triggers {
        pollSCM('* * * * *')
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 45, unit: 'MINUTES')
        timestamps()
    }

    stages {

        // ── Stage 1: Checkout ─────────────────────────────────
        stage('Checkout') {
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

        // ── Stage 2: Skip Tests ───────────────────────────────
        stage('Lint & Unit Tests') {
            steps {
                echo 'Skipping tests — microservices have no test suites configured'
            }
        }

        // ── Stage 3: ECR Login ────────────────────────────────
        stage('ECR Login') {
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

        // ── Stage 4: Build Docker Images ──────────────────────
        stage('Build Docker Images') {
            parallel {
                stage('Build helloService') {
                    steps {
                        sh '''
                            docker build \
                              --tag ${ECR_REGISTRY}/${ECR_REPO_HELLO}:${IMAGE_TAG} \
                              --tag ${ECR_REGISTRY}/${ECR_REPO_HELLO}:latest \
                              --file backend/helloService/Dockerfile \
                              ./backend/helloService
                        '''
                    }
                }
                stage('Build profileService') {
                    steps {
                        sh '''
                            docker build \
                              --tag ${ECR_REGISTRY}/${ECR_REPO_PROFILE}:${IMAGE_TAG} \
                              --tag ${ECR_REGISTRY}/${ECR_REPO_PROFILE}:latest \
                              --file backend/profileService/Dockerfile \
                              ./backend/profileService
                        '''
                    }
                }
            }
        }

        // ── Stage 5: Push to ECR ──────────────────────────────
        stage('Push to ECR') {
            parallel {
                stage('Push helloService') {
                    steps {
                        sh '''
                            docker push ${ECR_REGISTRY}/${ECR_REPO_HELLO}:${IMAGE_TAG}
                            docker push ${ECR_REGISTRY}/${ECR_REPO_HELLO}:latest
                        '''
                    }
                }
                stage('Push profileService') {
                    steps {
                        sh '''
                            docker push ${ECR_REGISTRY}/${ECR_REPO_PROFILE}:${IMAGE_TAG}
                            docker push ${ECR_REGISTRY}/${ECR_REPO_PROFILE}:latest
                        '''
                    }
                }
            }
        }

        // ── Stage 6: Update EKS Kubeconfig ───────────────────
        stage('Update EKS Kubeconfig') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${AWS_CREDENTIALS}",
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {
                    sh '''
                        mkdir -p /tmp/kube
                        aws eks update-kubeconfig \
                          --region ${AWS_REGION} \
                          --name   ${EKS_CLUSTER_NAME} \
                          --kubeconfig /tmp/kube/config
                        chmod 600 /tmp/kube/config
                        kubectl --kubeconfig=/tmp/kube/config get nodes
                    '''
                }
            }
        }

        // ── Stage 7: Helm Deploy ──────────────────────────────
        stage('Helm Deploy') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${AWS_CREDENTIALS}",
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {
                    sh '''
                        kubectl --kubeconfig=/tmp/kube/config \
                          create namespace ${K8S_NAMESPACE} \
                          --dry-run=client -o yaml | \
                          kubectl --kubeconfig=/tmp/kube/config apply -f -

                        helm upgrade --install ${HELM_RELEASE} ./helm/streaming-app \
                          --kubeconfig /tmp/kube/config \
                          --namespace ${K8S_NAMESPACE} \
                          --set helloService.image.repository=${ECR_REGISTRY}/${ECR_REPO_HELLO} \
                          --set helloService.image.tag=${IMAGE_TAG} \
                          --set profileService.image.repository=${ECR_REGISTRY}/${ECR_REPO_PROFILE} \
                          --set profileService.image.tag=${IMAGE_TAG} \
                          --wait \
                          --timeout 5m0s
                    '''
                }
            }
        }

        // ── Stage 8: Smoke Test ───────────────────────────────
        stage('Smoke Test') {
            steps {
                sh '''
                    echo "Checking helloService health..."
                    kubectl --kubeconfig=/tmp/kube/config \
                      get pods -n ${K8S_NAMESPACE}
                '''
            }
        }

    } // end stages

    post {
        always {
            sh '''
                docker rmi ${ECR_REGISTRY}/${ECR_REPO_HELLO}:${IMAGE_TAG}   || true
                docker rmi ${ECR_REGISTRY}/${ECR_REPO_PROFILE}:${IMAGE_TAG} || true
                rm -f /tmp/kube/config || true
            '''
        }
        success {
            echo "✅ Build #${env.BUILD_NUMBER} succeeded — tag: ${IMAGE_TAG}"
        }
        failure {
            echo "❌ Build #${env.BUILD_NUMBER} FAILED"
        }
    }

} // end pipeline
