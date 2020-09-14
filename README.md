# Task Walkthrough

## GitHub Repository Assets

Creating application web content in __content/index.html__
```
<!DOCTYPE html>
<html>
    <head>
        <title>Hello World</title>
    </head>
    <body>
        <h1>Hello World v1</h1>
    </body>
</html>
```

Changing NGINX configuration to combine all logs in one file __nginx-conf/default.conf__
```
server {
    listen       80;
    listen  [::]:80;
    server_name  localhost;

    #charset koi8-r;
    access_log  /var/log/nginx/mylogs.log  main;
    error_log   /var/log/nginx/mylogs.log;
    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
    }

    #error_page  404              /404.html;

    # redirect server error pages to the static page /50x.html
    #
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }

    # proxy the PHP scripts to Apache listening on 127.0.0.1:80
    #
    #location ~ \.php$ {
    #    proxy_pass   http://127.0.0.1;
    #}

    # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
    #
    #location ~ \.php$ {
    #    root           html;
    #    fastcgi_pass   127.0.0.1:9000;
    #    fastcgi_index  index.php;
    #    fastcgi_param  SCRIPT_FILENAME  /scripts$fastcgi_script_name;
    #    include        fastcgi_params;
    #}

    # deny access to .htaccess files, if Apache's document root
    # concurs with nginx's one
    #
    #location ~ /\.ht {
    #    deny  all;
    #}
}
```

Creating __Dockerfile__
```
FROM nginx
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx-conf /etc/nginx/conf.d
COPY content /usr/share/nginx/html

EXPOSE 80/tcp
```

Creating __.dockerignore__ file
```
.git
ansible
Jenkinsfile
README.md
```

## Testing application locally

Cloning GitHub repository to local host
```
$ git clone https://github.com/telraneng/myview.git
```

Building Docker image from __myview__ directory
```
$ docker build -t myapp:0.1.0 .
```

Running application locally
```
$ docker run -d --name myapp -p 8080:80 myapp:0.1.0
```

Verifying application content in Browser
```
http://127.0.0.1:8080
```

## Creating Infrastructure

Infrastructure units
```
jenkins
docker-registry
Swarm Cluster
  master
  worker
```

> In this flow we use Docker Machine with VirtualBox

Running infrastructure machines
```
$ for host in jenkins docker-registry master worker; do docker-machine create -d virtualbox $host; done
```

Verifying machines are up and running
```
$ docker-machine ls
NAME              ACTIVE   DRIVER       STATE     URL                         SWARM   DOCKER      ERRORS
docker-registry   -        virtualbox   Running   tcp://192.168.99.102:2376           v19.03.12
jenkins           *        virtualbox   Running   tcp://192.168.99.101:2376           v19.03.12
master            -        virtualbox   Running   tcp://192.168.99.103:2376           v19.03.12
worker            -        virtualbox   Running   tcp://192.168.99.104:2376           v19.03.12
```

Creating Swarm from *master* machine
```
$ docker swarm init --advertise-addr $(ip addr show eth1 | grep inet | head -1 | awk '{ print $2 }' | cut -d/ -f1)
```

Adding *worker* node to Swarm
```
$ docker swarm join --token SWMTKN-1-3kkv8cckpt6jpwznvdfxkx217q0c0kicm4lpntqp0zef3ua2ua-cro2n1qyzbwk9jpugqik0sgmw 192.168.99.103:2377
```

## Preparing Jenkins

Running Jenkins on *jenkins* machine
```
$ docker-machine ssh jenkins 'bash -c "docker run -d -p 8080:8080 -p 50000:50000 -v /var/run/docker.sock:/var/run/docker.sock -v /tmp/jenkins_home:/var/jenkins_home --privileged --name jenkins jenkins/jenkins:lts"'
```
docker run -d --name jenkinsdoc -p 8080:8080 -p 50000:50000 -v /var/run/docker.sock:/var/run/docker.sock -v $(which docker):$(which docker) -v /tmp/jenkins_home:/var/jenkins_home jenkins/jenkins:lts


Querying Jenkins initial admin password from __/var/jenkins_home/secrets/initialAdminPassword__
```
$ docker-machine ssh jenkins 'bash -c "docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"'
```

### Configuring Jenkis Docker Slave

Building jenkins-docker-slave Docker image from __jenkins-docker-slave/Dockerfile__
```
$ cd jenkins-docker-slave && docker build -t 192.168.99.107:5000/jenkins-docker-agent:latest .
```
```
FROM ubuntu:16.04 AS base

RUN apt-get update

RUN apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg-agent \
        software-properties-common \
        openjdk-8-jre \
        python \
        python-pip \
        git \
    vim

RUN apt-get clean

FROM base AS dockered

RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

RUN add-apt-repository \
        "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) \
        stable"

RUN apt-get update

RUN apt-get install -y \
        docker-ce="5:18.09.9~3-0~ubuntu-$(lsb_release -cs)" \
        docker-ce-cli="5:18.09.9~3-0~ubuntu-$(lsb_release -cs)" \
        containerd.io

RUN apt-get clean

FROM dockered AS jenkinswebapi

RUN easy_install jenkins-webapi

FROM jenkinswebapi AS agent
COPY slave.py /var/lib/jenkins/slave.py

WORKDIR /home/jenkins

ENV JENKINS_URL "http://192.168.99.108:8080"
ENV JENKINS_SLAVE_ADDRESS ""
#ENV JENKINS_USER "buildbot"
#ENV JENKINS_PASS "uveye123"
ENV SLAVE_NAME ""
ENV SLAVE_SECRET ""
ENV SLAVE_EXECUTORS "1"
ENV SLAVE_LABELS "uveye-agent"
ENV SLAVE_WORKING_DIR ""
ENV CLEAN_WORKING_DIR "true"

CMD [ "python", "-u", "/var/lib/jenkins/slave.py" ]
```

Pushing Docker image to local Docker Registry
```
$ docker push 192.168.99.107:5000/jenkins-docker-agent:latest
```

Pullong Docker image from local Docker Registry on *master* node
```
$ docker pull 192.168.99.107:5000/jenkins-docker-agent:latest
```

> Configuring Jenkins Cloud to use jenkins-docker-slave:latest

### Jenkins Build Job

Creating Jenkins Pipeline Job

Creating Jenkinsfile in gt repository (we can use DSL for docker operations instead of Shell commands)
```
node(label: 'uveye-agent') {
    def image = "192.168.99.107:5000/myapp:0.1.0-r${BUILD_NUMBER}"
    try {
        stage('Clone') {
            git branch: 'master', credentialsId: 'buildbot', url: 'https://github.com/telraneng/myview.git'
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
```

Jenkins Job Console output
```
Started by user admin
Obtained Jenkinsfile from git https://github.com/telraneng/myview.git
Running in Durability level: MAX_SURVIVABILITY
[Pipeline] Start of Pipeline
[Pipeline] node
Running on uveye-agent-00003rn5etdgp on uveye in /home/jenkins/workspace/hello-world-ci
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Clone)
[Pipeline] git
Selected Git installation does not exist. Using Default
The recommended git tool is: NONE
using credential buildbot
Cloning the remote Git repository
Cloning repository https://github.com/telraneng/uveye.git
 > git init /home/jenkins/workspace/hello-world-ci # timeout=10
Fetching upstream changes from https://github.com/telraneng/uveye.git
 > git --version # timeout=10
 > git --version # 'git version 2.7.4'
using GIT_ASKPASS to set credentials 
 > git fetch --tags --progress https://github.com/telraneng/uveye.git +refs/heads/*:refs/remotes/origin/* # timeout=10
Avoid second fetch
Checking out Revision 8480ca528a7f715aab1d7124562e9ff0082b8380 (refs/remotes/origin/master)
 > git config remote.origin.url https://github.com/telraneng/uveye.git # timeout=10
 > git config --add remote.origin.fetch +refs/heads/*:refs/remotes/origin/* # timeout=10
 > git rev-parse refs/remotes/origin/master^{commit} # timeout=10
 > git rev-parse refs/remotes/origin/origin/master^{commit} # timeout=10
 > git config core.sparsecheckout # timeout=10
 > git checkout -f 8480ca528a7f715aab1d7124562e9ff0082b8380 # timeout=10
 > git branch -a -v --no-abbrev # timeout=10
 > git checkout -b master 8480ca528a7f715aab1d7124562e9ff0082b8380 # timeout=10
Commit message: "Jenkinsfile added. Jenkins Docker Slave prepared"
 > git rev-list --no-walk 9ce8d650c9c0ef326278d30e65ff0f492b0e0f38 # timeout=10
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Build Docker Image)
[Pipeline] sh
+ docker build -t 192.168.99.107:5000/myapp:0.1.0-r6 .
Sending build context to Docker daemon  14.85kB

Step 1/5 : FROM nginx
 ---> 7e4d58f0e5f3
Step 2/5 : RUN rm /etc/nginx/conf.d/default.conf
 ---> Using cache
 ---> 94d7fd113306
Step 3/5 : COPY nginx-conf /etc/nginx/conf.d
 ---> Using cache
 ---> 900123c69c7c
Step 4/5 : COPY content /usr/share/nginx/html
 ---> Using cache
 ---> 85ec0b14f984
Step 5/5 : EXPOSE 80/tcp
 ---> Using cache
 ---> cff31e2d0a63
Successfully built cff31e2d0a63
Successfully tagged 192.168.99.107:5000/myapp:0.1.0-r6
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Push Docker Image to Registry)
[Pipeline] sh
+ docker push 192.168.99.107:5000/myapp:0.1.0-r6
The push refers to repository [192.168.99.107:5000/myapp]
d840ee8e771c: Preparing
7e00f38ff800: Preparing
a777260d59c6: Preparing
908cf8238301: Preparing
eabfa4cd2d12: Preparing
60c688e8765e: Preparing
f431d0917d41: Preparing
07cab4339852: Preparing
60c688e8765e: Waiting
f431d0917d41: Waiting
07cab4339852: Waiting
908cf8238301: Layer already exists
eabfa4cd2d12: Layer already exists
a777260d59c6: Layer already exists
d840ee8e771c: Layer already exists
7e00f38ff800: Layer already exists
60c688e8765e: Layer already exists
07cab4339852: Layer already exists
f431d0917d41: Layer already exists
0.1.0-r6: digest: sha256:ee7fc31340218ade720f02ae42a5c8d41cdbf88c062a9e388a2a7c08f0113c2a size: 1983
[Pipeline] }
[Pipeline] // stage
[Pipeline] echo
Send Mail!!!
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
Finished: SUCCESS
```

### Jenkins Deploy Job

Creating Jenkins Pipeline job for service deploy
```
node(label: 'uveye-agent') {
    def image = "192.168.99.107:5000/myapp:0.1.0-r${BUILD_NUMBER}"
    try {
        stage('Test Registry') {
            sh "curl http://192.168.99.107:5000/v2/myapp/tags/list | jq '.tags'"
            tags = sh (script: "curl http://192.168.99.107:5000/v2/myapp/tags/list | jq '.tags'", returnStdout: true)
            println(tags)
            sh "docker service update --image 192.168.99.107:5000/myapp:${IMAGE_TAG} helloworld"
        }
    } catch (e){
        currentBuild.result = 'FAILURE'
        throw e
    } finally {
        println("Send Mail!!!")
    }
}
```

