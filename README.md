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
$ git clone https://github.com/telraneng/uveye.git
```

Building Docker image from __uveye__ directory
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

Building jenkins-docker-slave Docker image from __jenkins-docker-slave/Dockerfile
```
$ cd jenkins-docker-slave && docker build -t jenkins-docker-slave:latest .
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

Saving Docker image and moving it to *worker* machine
```
$ docker save jenkins-docker-slave:latest | qzip > jenkins-docker-slave.tgz
$ scp jenkins-docker-slave.tgz docker@192.168.99.105:~/
```

Loading Docker image from archive on *worker* node
```
$ docker load < jenkins-docker-slave.tgz
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
```



