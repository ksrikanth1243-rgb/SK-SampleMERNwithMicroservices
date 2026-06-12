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

        stage('Lint & Unit Tests') {
            steps {
                echo 'Skipping tests — microservices have no test suites configured'
            }
        }

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

        stage('Smoke Test') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${AWS_CREDENTIALS}",
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {
                    sh '''
                        kubectl --kubeconfig=/tmp/kube/config \
                          get pods -n ${K8S_NAMESPACE}
                    '''
                }
            }
        }

    }

    post {
        always {
            sh '''
                docker rmi ${ECR_REGISTRY}/${ECR_REPO_HELLO}:${IMAGE_TAG}   || true
                docker rmi ${ECR_REGISTRY}/${ECR_REPO_PROFILE}:${IMAGE_TAG} || true
                rm -f /tmp/kube/config || true
            '''
        }
        success {
            echo "SUCCESS: Build #${env.BUILD_NUMBER} tag: ${IMAGE_TAG}"
        }
        failure {
            echo "FAILED: Build #${env.BUILD_NUMBER}"
        }
    }

}
