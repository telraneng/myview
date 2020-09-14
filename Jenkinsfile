node(label: 'myview-agent') {
    def image = "192.168.99.107:5000/myapp"
    try {
        stage('Clone') {
            git branch: 'master', credentialsId: 'buildbot', url: 'https://github.com/telraneng/myview.git'
        }
        stage('Build Docker Image') {
            sh "docker build -t ${image}:0.1.0-r${BUILD_NUMBER} -t ${image}:latest ."
        }
        stage('Push Docker Image to Registry') {
            sh "docker push ${image}:0.1.0-r${BUILD_NUMBER}"
        }
    } catch (e){
        currentBuild.result = 'FAILURE'
        throw e
    } finally {
        println("Send Mail!!!")
    }
}
