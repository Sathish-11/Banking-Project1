pipeline {
    agent any
    environment {
        DOCKER_IMG = "harbor.local/myproject/bankingapp"
        DOCKER_TAG = "${env.BUILD_NUMBER ?: 'latest'}"
    }
    stages {
        stage('Git Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/Sathish-11/Banking-Project1.git'
            }
        }
        stage('Create Package') {
            steps{
                script {
                    sh 'mvn clean package -D skipTests'
                }
            }
        }
        stage('Code-Scan') {
            steps {
              script {
                def scannerhome = tool name: 'sonarscanner', type: 'hudson.plugins.sonar.SonarRunnerInstallation'
                withCredentials([string(credentialsId: 'sonar-secret', variable: 'SONAR_SECRET')]) {
                    sh """
                            ${scannerhome}/bin/sonar-scanner \
                            -Dsonar.projectKey=sample-project \
                            -Dsonar.host.url=http://172.31.39.177:9000 \
                            -Dsonar.login=${SONAR_SECRET} \
                            -Dsonar.java.binaries=target/classes
                       """
                }
              }   
            }
        }
        stage('Code Test') {
            steps {
                sh 'mvn clean test'
            }
        }
        stage('Code Build') {
            steps {
                sh 'docker build -t ${DOCKER_IMG}:${DOCKER_TAG} .'
            }
        }
        stage('Push image to Registry') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'Harbor-Registry', passwordVariable: 'DOCKER_PASS', usernameVariable: 'DOCKER_USER')]) {
                    sh """
                        echo "$DOCKER_PASS" | docker login harbor.local -u $DOCKER_USER --password-stdin
                        docker push ${DOCKER_IMG}:${DOCKER_TAG}
                       """
                   }
                }
            }
        }
        stage('Deploy into k8s') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'KUBE_CONFIG_FILE', variable: 'KUBE_CONFIG_FILE')]) {
                        sh """
                            envsubst < deployment-service.yaml |
                            kubectl --kubeconfig='$KUBE_CONFIG_FILE' apply -f -
                           """
                    }
                }
            }
        }
    }
    post {
        success {
            echo "Bankapp docker image deployed into k8s cluster with NOdeport service"
        }
        failure {
            echo "Pipeline fails to deploy app on k8s cluster, Check deployment logs on control plane to resolve the issue"
        }
    }
}
