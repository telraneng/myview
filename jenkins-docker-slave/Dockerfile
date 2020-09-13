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
