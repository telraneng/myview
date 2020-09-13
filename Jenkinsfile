node(label: 'uveye-agent') {
    def image = "192.168.99.107:5000/myapp:0.1.0-r${BUILD_NUMBER}"
    try {
        stage('Clone') {
            git branch: 'master', credentialsId: 'buildbot', url: 'https://github.com/telraneng/uveye.git'
        }
        stage('Build Docker Image') {
            sh "docker build -t ${image} ."
        }
        stage('Push Docker Image to Registry') {
            sh "docker push ${image}"
        }
    } catch (e){
        currentBuild.result = 'FAILURE'
        throw e
    } finally {
        println("Send Mail!!!")
    }
}
