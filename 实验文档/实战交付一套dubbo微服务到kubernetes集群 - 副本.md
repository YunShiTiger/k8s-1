# 实验文档2：实战交付一套dubbo微服务到kubernetes集群

------

# 基础架构

| 主机名 | 角色                          | ip        |
| :----- | :---------------------------- | :-------- |
| m1     | master节点1，zk1              | 10.0.0.31 |
| m2     | master节点2，zk2              | 10.0.0.32 |
| m3     | master节点3，zk3              | 10.0.0.33 |
| manege | 管理节点，jenkins、docker仓库 | 10.0.0.20 |
| slb01  | slb                           | 10.0.0.11 |
| slb02  | slb                           | 10.0.0.12 |
| n1     | node节点01                    | 10.0.0.41 |
| n2     | node节点02                    | 10.0.0.42 |

# 部署zookeeper

## 安装jdk1.8（3台zk角色主机）

> jdk下载地址
> [jdk1.6](https://www.oracle.com/technetwork/java/javase/downloads/java-archive-downloads-javase6-419409.html)
> [jdk1.7](https://www.oracle.com/technetwork/java/javase/downloads/java-archive-downloads-javase7-521261.html)
> [jdk1.8](https://www.oracle.com/technetwork/java/javase/downloads/jdk8-downloads-2133151.html)

```bash
mkdir -p /opt/java
tar xf /opt/src/jdk-8u251-linux-x64.tar.gz -C /opt/java
ln -s /opt/java/jdk1.8.0_251 /opt/java/jdk
cat << 'EOF' >>/etc/profile
export JAVA_HOME=/opt/java/jdk
export PATH=$JAVA_HOME/bin:$JAVA_HOME/jre/bin:$PATH
export CLASSPATH=.:$JAVA_HOME/lib:$JAVA_HOME/jre/lib:$JAVA_HOME/lib/tools.jar
EOF
```

加载环境变量，验证版本

```bash
source /etc/profile
java -version
```

## 安装zookeeper（3台zk角色主机）

> zk下载地址
> [zookeeper](https://archive.apache.org/dist/zookeeper/)

### 解压、配置

```bash
mkdir -p /opt/zookeeper
tar xf /opt/src/apache-zookeeper-3.5.8-bin.tar.gz -C /opt/zookeeper
ln -s /opt/zookeeper/apache-zookeeper-3.5.8-bin /opt/zookeeper/zookeeper
mkdir -p /data/zookeeper/{data,logs}
cat << EOF >/opt/zookeeper/zookeeper/conf/zoo.cfg
tickTime=2000
initLimit=10
syncLimit=5
clientPort=2181
dataDir=/data/zookeeper/data
dataLogDir=/data/zookeeper/logs
server.1=zk1.wzxmt.com:2888:3888
server.2=zk2.wzxmt.com:2888:3888
server.3=zk3.wzxmt.com:2888:3888
EOF
```

**注意：**各节点zk配置相同。

**zookeeper myid各节点一定要不一样**

m1上：

```
echo '1' > /data/zookeeper/data/myid
```

m2上：

```
echo '2' > /data/zookeeper/data/myid
```

m3上：

```
echo '3' > /data/zookeeper/data/myid
```

### 做dns解析

manege

```bash
zk1	60 IN A 10.0.0.31
zk2	60 IN A 10.0.0.32
zk3	60 IN A 10.0.0.33
```

### 依次启动

```bash
/opt/zookeeper/zookeeper/bin/zkServer.sh start
```

查看状态

```bash
[root@m1 src]# /opt/zookeeper/zookeeper/bin/zkServer.sh status
Mode: follower
[root@m2 src]# /opt/zookeeper/zookeeper/bin/zkServer.sh status
Mode: leader
[root@m3 src]# /opt/zookeeper/zookeeper/bin/zkServer.sh status
Mode: follower
```

# 部署jenkins

## 准备镜像

> [jenkins官网](https://jenkins.io/download/)
> [jenkins镜像](https://hub.docker.com/r/jenkins/jenkins)

在运维主机下载官网上的稳定版

```bash
docker pull jenkins/jenkins:2.195-centos
```

## 自定义Dockerfile

在运维主机上编辑dockerfile

```bash
mkdir -p /data/dockerfile/jenkins
cd /data/dockerfile/jenkins
cat << EOF >Dockerfile
FROM jenkins/jenkins:2.195-centos
USER root
RUN /bin/cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&\ 
    echo 'Asia/Shanghai' >/etc/timezone
ADD id_rsa /root/.ssh/id_rsa
ADD config.json /root/.docker/config.json
ADD get-docker.sh /get-docker.sh
RUN echo "    StrictHostKeyChecking no" >> /etc/ssh/sshd_config &&\
    /get-docker.sh
EOF
```

这个Dockerfile里我们主要做了以下几件事

- 设置容器用户为root
- 设置容器内的时区
- 将ssh私钥加入（使用git拉代码时要用到，配对的公钥应配置在gitlab中）
- 加入了登录自建harbor仓库的config文件
- 修改了ssh客户端的
- 安装一个docker的客户端

生成ssh密钥对：

```bash
ssh-keygen -t rsa -b 2048 -C "wzxmt.com@qq.com" -N "" -f /root/.ssh/id_rsa
```

get-docker.sh

```bash
cat  << 'EOF' >get-docker.sh
#!/bin/bash
cd /etc/yum.repos.d
mv /etc/yum.repos.d/{CentOS-Base.repo,.bak}
mv /etc/yum.repos.d/{epel.repo,bak}
curl https://mirrors.aliyun.com/repo/Centos-7.repo -o CentOS-Base.repo 
curl https://mirrors.aliyun.com/repo/epel-7.repo -o epel.repo
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum makecache fast
rpm --import https://mirrors.aliyun.com/docker-ce/linux/centos/gpg
yum makecache fast
yum install -y docker-ce-18.09.9-3.el7
EOF
```

cat /root/.docker/config.json

```
{
	"auths": {
		"harbor.wzxmt.com": {
			"auth": "YWRtaW46YWRtaW4="
		}
	},
	"HttpHeaders": {
		"User-Agent": "Docker-Client/19.03.8 (linux)"
	}
```

## 制作自定义镜像

```bash
cp -r /root/.ssh/id_rsa ./
cp -r /root/.docker/config.json ./
chmod +x get-docker.sh
ls #查看Dokerfile所需文件
#config.json  Dockerfile  get-docker.sh  id_rsa
docker build . -t harbor.wzxmt.com/infra/jenkins:v2.195
docker push harbor.wzxmt.com/infra/jenkins:v2.195
```

## 准备共享存储

运维主机，以及所有运算节点上：

```
yum install nfs-utils -y
```

- 配置NFS服务

运维主机：

```
cat<< EOF >/etc/exports
/data/nfs-volume 10.0.0.0/24(rw,no_root_squash)
EOF
```

- 启动NFS服务

运维主机上：

```bash
mkdir -p /data/nfs-volume
systemctl start nfs
systemctl enable nfs
```

## 准备资源配置清单

运维主机上：

```
/data/k8s-yaml
mkdir /data/k8s-yaml/jenkins && mkdir /data/nfs-volume/jenkins_home && cd /data/k8s-yaml/jenkins
```

- [Deployment](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#jenkins-yaml-1)
- [Service](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#jenkins-yaml-2)
- [Ingress](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#jenkins-yaml-3)

vi deployment.yaml

```
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: jenkins
  namespace: infra
  labels: 
    name: jenkins
spec:
  replicas: 1
  selector:
    matchLabels: 
      name: jenkins
  template:
    metadata:
      labels: 
        app: jenkins 
        name: jenkins
    spec:
      volumes:
      - name: data
        nfs: 
          server: hdss7-200
          path: /data/nfs-volume/jenkins_home
      - name: docker
        hostPath: 
          path: /run/docker.sock
          type: ''
      containers:
      - name: jenkins
        image: harbor.od.com/infra/jenkins:v2.164.1
        ports:
        - containerPort: 8080
          protocol: TCP
        env:
        - name: JAVA_OPTS
          value: -Xmx512m -Xms512m
        resources:
          limits: 
            cpu: 500m
            memory: 1Gi
          requests: 
            cpu: 500m
            memory: 1Gi
        volumeMounts:
        - name: data
          mountPath: /var/jenkins_home
        - name: docker
          mountPath: /run/docker.sock
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
        imagePullPolicy: IfNotPresent
      imagePullSecrets:
      - name: harbor
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      securityContext: 
        runAsUser: 0
      schedulerName: default-scheduler
  strategy:
    type: RollingUpdate
    rollingUpdate: 
      maxUnavailable: 1
      maxSurge: 1
  revisionHistoryLimit: 7
  progressDeadlineSeconds: 600
```

## 应用资源配置清单

任意一个k8s运算节点上

```
[root@hdss7-21 ~]# kubectl create namespace infra
[root@hdss7-21 ~]# kubectl apply -f  http://k8s-yaml.od.com/jenkins/deployment.yaml
[root@hdss7-21 ~]# kubectl apply -f  http://k8s-yaml.od.com/jenkins/svc.yaml
[root@hdss7-21 ~]# kubectl apply -f  http://k8s-yaml.od.com/jenkins/ingress.yaml

[root@hdss7-21 ~]# kubectl get pods -n infra|grep jenkins
NAME                                READY     STATUS    RESTARTS   AGE
jenkins-84455f9675-jpkr8            1/1       Running   0          0d

[root@hdss7-21 ~]# kubectl get svc -n infra|grep jenkins
NAME           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
jenkins        ClusterIP   None             <none>        8080/TCP   0d

[root@hdss7-21 ~]# kubectl get ingress -n infra|grep jenkins
NAME           HOSTS                          ADDRESS   PORTS     AGE
jenkins        jenkins.od.com                           80        0d
```



## 解析域名

`HDSS7-11.host.com`上

复制

```
/var/named/od.com.zone
jenkins	60 IN A 10.4.7.10
```



## 浏览器访问

[http://jenkins.od.com](http://jenkins.od.com/)

## 页面配置jenkins

![jenkins初始化页面](https://blog.stanley.wang/images/jenkins-init.png)

### 初始化密码

复制

```
/data/nfs-volume/jenkins_home/secrets/initialAdminPassword
[root@hdss7-200 secrets]# cat initialAdminPassword 
08d17edc125444a28ad6141ffdfd5c69
```

### 安装插件

![jenkins安装页面](https://blog.stanley.wang/images/jenkins-install.png)

### 设置用户

![jenkins设置用户](https://blog.stanley.wang/images/jenkins-user.png)

### 完成安装

![jenkins完成安装1](https://blog.stanley.wang/images/jenkins-url.png)
![jenkins完成安装2](https://blog.stanley.wang/images/jenkins-ready.png)

### 使用admin登录

![jenkins登录](https://blog.stanley.wang/images/jenkins-welcome.png)

### 安装Blue Ocean插件

- Manage Jenkins
- Manage Plugins
- Available
- Blue Ocean

### 调整安全选项

- Manage Jenkins
- Configure Global Security
- Allow anonymous read access

## 配置New job

- create new jobs

- Enter an item name

  > dubbo-demo

- Pipeline -> OK

- Discard wzxmt builds

  > Days to keep builds : 3
  > Max # of builds to keep : 30

- This project is parameterized

1. Add Parameter -> String Parameter

   > Name : app_name
   > Default Value :
   > Description : project name. e.g: dubbo-demo-service

2. Add Parameter -> String Parameter

   > Name : image_name
   > Default Value :
   > Description : project docker image name. e.g: app/dubbo-demo-service

3. Add Parameter -> String Parameter

   > Name : git_repo
   > Default Value :
   > Description : project git repository. e.g: https://gitee.com/stanleywang/dubbo-demo-service.git

4. Add Parameter -> String Parameter

   > Name : git_ver
   > Default Value :
   > Description : git commit id of the project.

5. Add Parameter -> String Parameter

   > Name : add_tag
   > Default Value :
   > Description : project docker image tag, date_timestamp recommended. e.g: 190117_1920

6. Add Parameter -> String Parameter

   > Name : mvn_dir
   > Default Value : ./
   > Description : project maven directory. e.g: ./

7. Add Parameter -> String Parameter

   > Name : target_dir
   > Default Value : ./target
   > Description : the relative path of target file such as .jar or .war package. e.g: ./dubbo-server/target

8. Add Parameter -> String Parameter

   > Name : mvn_cmd
   > Default Value : mvn clean package -Dmaven.test.skip=true
   > Description : maven command. e.g: mvn clean package -e -q -Dmaven.test.skip=true

9. Add Parameter -> Choice Parameter

   > Name : base_image
   > Default Value :
   >
   > - base/jre7:7u80
   > - base/jre8:8u112
   >   Description : project base image list in harbor.od.com.

10. Add Parameter -> Choice Parameter

    > Name : maven
    > Default Value :
    >
    > - 3.6.0-8u181
    > - 3.2.5-6u025
    > - 2.2.1-6u025
    >   Description : different maven edition.

## Pipeline Script

复制

```
pipeline {
  agent any 
    stages {
      stage('pull') { //get project code from repo 
        steps {
          sh "git clone ${params.git_repo} ${params.app_name}/${env.BUILD_NUMBER} && cd ${params.app_name}/${env.BUILD_NUMBER} && git checkout ${params.git_ver}"
        }
      }
      stage('build') { //exec mvn cmd
        steps {
          sh "cd ${params.app_name}/${env.BUILD_NUMBER}  && /var/jenkins_home/maven-${params.maven}/bin/${params.mvn_cmd}"
        }
      }
      stage('package') { //move jar file into project_dir
        steps {
          sh "cd ${params.app_name}/${env.BUILD_NUMBER} && cd ${params.target_dir} && mkdir project_dir && mv *.jar ./project_dir"
        }
      }
      stage('image') { //build image and push to registry
        steps {
          writeFile file: "${params.app_name}/${env.BUILD_NUMBER}/Dockerfile", text: """FROM harbor.od.com/${params.base_image}
ADD ${params.target_dir}/project_dir /opt/project_dir"""
          sh "cd  ${params.app_name}/${env.BUILD_NUMBER} && docker build -t harbor.od.com/${params.image_name}:${params.git_ver}_${params.add_tag} . && docker push harbor.od.com/${params.image_name}:${params.git_ver}_${params.add_tag}"
        }
      }
    }
}
```

# 最后的准备工作

## 检查jenkins容器里的docker客户端

进入jenkins的docker容器里，检查docker客户端是否可用。

复制

```
[root@hdss7-22 ~]# docker exec -ti 52e250789b78 bash
root@52e250789b78:/# docker ps -a
```



## 检查jenkins容器里的SSH key

进入jenkins的docker容器里，检查ssh连接git仓库，确认是否能拉到代码。

复制

```
[root@hdss7-22 ~]# docker exec -ti 52e250789b78 bash
root@52e250789b78:/# ssh -i /root/.ssh/id_rsa -T git@gitee.com                                                                                              
Hi Anonymous! You've successfully authenticated, but GITEE.COM does not provide shell access.
Note: Perhaps the current use is DeployKey.
Note: DeployKey only supports pull/fetch operations
```



## 部署maven软件

[maven官方下载地址](http://maven.apache.org/docs/history.html)
在运维主机`HDSS7-200.host.com`上二进制部署，这里部署maven-3.6.0版

复制

```
/opt/src
[root@hdss7-22 src]# ls -l
total 8852
-rw-r--r-- 1 root root 9063587 Jan  17 19:57 apache-maven-3.6.0-bin.tar.gz
[root@hdss7-200 src]# tar xf apache-maven-3.6.0-bin.tar.gz -C /data/nfs-volume/jenkins_home/maven-3.6.0-8u181
[root@hdss7-200 src]# mv /data/nfs-volume/jenkins_home/apache-maven-3.6.0/ /data/nfs-volume/jenkins_home/maven-3.6.0-8u181
[root@hdss7-200 src]# ls -ld /data/nfs-volume/jenkins_home/maven-3.6.0-8u181
drwxr-xr-x 6 root root 99 Jan  17 19:58 /data/nfs-volume/jenkins_home/maven-3.6.0-8u181
```



设置国内镜像源

复制

```
/data/nfs-volume/jenkins_home/maven-3.6.0-8u181/conf/setting.xml
<mirror>
  <id>alimaven</id>
  <name>aliyun maven</name>
  <url>http://maven.aliyun.com/nexus/content/groups/public/</url>
  <mirrorOf>central</mirrorOf>        
</mirror>
```



其他版本略

## 制作dubbo微服务的底包镜像

运维主机`HDSS7-200.host.com`上

1. 自定义Dockerfile

复制

```
/data/dockerfile/jre8/Dockerfile
FROM stanleyws/jre8:8u112
RUN /bin/cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&\
    echo 'Asia/Shanghai' >/etc/timezone
ADD config.yml /opt/prom/config.yml
ADD jmx_javaagent-0.3.1.jar /opt/prom/
WORKDIR /opt/project_dir
ADD entrypoint.sh /entrypoint.sh
CMD ["/entrypoint.sh"]
```

- [config.yml](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#jre-dockerfile-1)
- [jmx_javaagent-0.3.1.jar](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#jre-dockerfile-2)
- [entrypoint.sh](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#jre-dockerfile-3)

vi config.yml

复制

```
---
rules:
  - pattern: '.*'
```

1. 制作dubbo服务docker底包

复制

```
/data/dockerfile/jre8
[root@hdss7-200 jre8]# ls -l
total 372
-rw-r--r-- 1 root root     29 Jan  17 19:09 config.yml
-rw-r--r-- 1 root root    287 Jan  17 19:06 Dockerfile
-rwxr--r-- 1 root root    250 Jan  17 19:11 entrypoint.sh
-rw-r--r-- 1 root root 367417 May 10  2018 jmx_javaagent-0.3.1.jar

[root@hdss7-200 jre8]# docker build . -t harbor.od.com/base/jre8:8u112
Sending build context to Docker daemon 372.2 kB
Step 1 : FROM stanleyws/jre8:8u112
 ---> fa3a085d6ef1
Step 2 : RUN /bin/cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&    echo 'Asia/Shanghai' >/etc/timezone
 ---> Using cache
 ---> 5da5ab0b1a48
Step 3 : ADD config.yml /opt/prom/config.yml
 ---> Using cache
 ---> 70d3ebfe88f5
Step 4 : ADD jmx_javaagent-0.3.1.jar /opt/prom/
 ---> Using cache
 ---> 08b38a0684a8
Step 5 : WORKDIR /opt/project_dir
 ---> Using cache
 ---> f06adf17fb69
Step 6 : ADD entrypoint.sh /entrypoint.sh
 ---> e34f185d5c52
Removing intermediate container ee213576ca0e
Step 7 : CMD /entrypoint.sh
 ---> Running in 655f594bcbe2
 ---> 47852bc0ade9
Removing intermediate container 655f594bcbe2
Successfully built 47852bc0ade9

[root@hdss7-200 jre8]# docker push harbor.od.com/base/jre8:8u112
The push refers to a repository [harbor.od.com/base/jre8]
0b2b753b122e: Pushed 
67e1b844d09c: Pushed 
ad4fa4673d87: Pushed 
0ef3a1b4ca9f: Pushed 
052016a734be: Pushed 
0690f10a63a5: Pushed 
c843b2cf4e12: Pushed 
fddd8887b725: Pushed 
42052a19230c: Pushed 
8d4d1ab5ff74: Pushed 
8u112: digest: sha256:252e3e869039ee6242c39bdfee0809242e83c8c3a06830f1224435935aeded28 size: 2405
```

**注意：**jre7底包制作类似，这里略

# 交付dubbo微服务至kubernetes集群

## dubbo服务提供者（dubbo-demo-service）

### 通过jenkins进行一次CI

打开jenkins页面，使用admin登录，准备构建`dubbo-demo`项目

![jenkins构建](https://blog.stanley.wang/images/jenkins-firstbuild.png)
点`Build with Parameters`

![jenkins构建详情](https://blog.stanley.wang/images/jenkins-builddetail.png)
依次填入/选择：

- app_name

  > dubbo-demo-service

- image_name

  > app/dubbo-demo-service

- git_repo

  > https://gitee.com/stanleywang/dubbo-demo-service.git

- git_ver

  > master

- add_tag

  > 190117_1920

- mvn_dir

  > /

- target_dir

  > ./dubbo-server/target

- mvn_cmd

  > mvn clean package -Dmaven.test.skip=true

- base_image

  > base/jre8:8u112

- maven

  > 3.6.0-8u181

点击`Build`进行构建，等待构建完成。

test $? -eq 0 && 成功，进行下一步 || 失败，排错直到成功

### 检查harbor仓库内镜像

![harbor仓库内镜像](https://blog.stanley.wang/images/harbor-firstci.png)

### 准备k8s资源配置清单

运维主机`HDSS7-200.host.com`上，准备资源配置清单：

复制

```
/data/k8s-yaml/dubbo-demo-service/deployment.yaml
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: dubbo-demo-service
  namespace: app
  labels: 
    name: dubbo-demo-service
spec:
  replicas: 1
  selector:
    matchLabels: 
      name: dubbo-demo-service
  template:
    metadata:
      labels: 
        app: dubbo-demo-service
        name: dubbo-demo-service
    spec:
      containers:
      - name: dubbo-demo-service
        image: harbor.od.com/app/dubbo-demo-service:master_190117_1920
        ports:
        - containerPort: 20880
          protocol: TCP
        env:
        - name: JAR_BALL
          value: dubbo-server.jar
        imagePullPolicy: IfNotPresent
      imagePullSecrets:
      - name: harbor
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      securityContext: 
        runAsUser: 0
      schedulerName: default-scheduler
  strategy:
    type: RollingUpdate
    rollingUpdate: 
      maxUnavailable: 1
      maxSurge: 1
  revisionHistoryLimit: 7
  progressDeadlineSeconds: 600
```



### 应用资源配置清单

在任意一台k8s运算节点执行：

复制

```
[root@hdss7-21 ~]# kubectl apply -f http://k8s-yaml.od.com/dubbo-demo-service/deployment.yaml
deployment.extensions/dubbo-demo-service created
```



### 检查docker运行情况及zk里的信息

复制

```
/opt/zookeeper/bin/zkCli.sh
[root@hdss7-11 ~]# /opt/zookeeper/bin/zkCli.sh -server localhost
[zk: localhost(CONNECTED) 0] ls /dubbo
[com.od.dubbotest.api.HelloService]
```

## dubbo-monitor工具

[dubbo-monitor源码包](https://github.com/Jeromefromcn/dubbo-monitor.git)

### 准备docker镜像

#### 下载源码

下载到运维主机`HDSS7-200.host.com`上

复制

```
/opt/src
[root@hdss7-200 src]# ls -l|grep dubbo-monitor
drwxr-xr-x 4 root root      81 Jan  17 13:58 dubbo-monitor
```



#### 修改配置

复制

```
/opt/src/dubbo-monitor/dubbo-monitor-simple/conf/dubbo_origin.properties
dubbo.registry.address=zookeeper://zk1.od.com:2181?backup=zk2.od.com:2181,zk3.od.com:2181
dubbo.protocol.port=20880
dubbo.jetty.port=8080
dubbo.jetty.directory=/dubbo-monitor-simple/monitor
dubbo.statistics.directory=/dubbo-monitor-simple/statistics
dubbo.log4j.file=logs/dubbo-monitor.log
```

#### 制作镜像

1. 准备环境

   复制

   ```
   [root@hdss7-200 src]# mkdir /data/dockerfile/dubbo-monitor
   [root@hdss7-200 src]# cp -a dubbo-monitor/* /data/dockerfile/dubbo-monitor/
   [root@hdss7-200 src]# cd /data/dockerfile/dubbo-monitor/
   [root@hdss7-200 dubbo-monitor]# sed -r -i -e '/^nohup/{p;:a;N;$!ba;d}'  ./dubbo-monitor-simple/bin/start.sh && sed  -r -i -e "s%^nohup(.*)%exec \1%"  ./dubbo-monitor-simple/bin/start.sh
   ```

2. 准备Dockerfile

   复制

   ```
   /data/dockerfile/dubbo-monitor/Dockerfile
   FROM jeromefromcn/docker-alpine-java-bash
   MAINTAINER Jerome Jiang
   COPY dubbo-monitor-simple/ /dubbo-monitor-simple/
   CMD /dubbo-monitor-simple/bin/start.sh
   ```

3. build镜像

   复制

   ```
   [root@hdss7-200 dubbo-monitor]# docker build . -t harbor.od.com/infra/dubbo-monitor:latest
   Sending build context to Docker daemon 26.21 MB
   Step 1 : FROM harbor.od.com/base/jre7:7u80
    ---> dbba4641da57
   Step 2 : MAINTAINER Stanley Wang
    ---> Running in 8851a3c55d4b
    ---> 6266a6f15dc5
   Removing intermediate container 8851a3c55d4b
   Step 3 : COPY dubbo-monitor-simple/ /opt/dubbo-monitor/
    ---> f4e0a9067c5c
   Removing intermediate container f1038ecb1055
   Step 4 : WORKDIR /opt/dubbo-monitor
    ---> Running in 4056339d1b5a
    ---> e496e2d3079e
   Removing intermediate container 4056339d1b5a
   Step 5 : CMD /opt/dubbo-monitor/bin/start.sh
    ---> Running in c33b8fb98326
    ---> 97e40c179bbe
   Removing intermediate container c33b8fb98326
   Successfully built 97e40c179bbe
   
   [root@hdss7-200 dubbo-monitor]# docker push harbor.od.com/infra/dubbo-monitor:latest
   The push refers to a repository [harbor.od.com/infra/dubbo-monitor]
   750135a87545: Pushed 
   0b2b753b122e: Pushed 
   5b1f1b5295ff: Pushed 
   d54f1d9d76d3: Pushed 
   8d51c20d6553: Pushed 
   106b765202e9: Pushed 
   c6698ca565d0: Pushed 
   50ecb880731d: Pushed 
   fddd8887b725: Pushed 
   42052a19230c: Pushed 
   8d4d1ab5ff74: Pushed 
   190107_1930: digest: sha256:73007a37a55ecd5fd72bc5b36d2ab0bb639c96b32b7879984d5cdbc759778790 size: 2617
   ```

### 解析域名

在DNS主机`HDSS7-11.host.com`上：

复制

```
/var/named/od.com.zone
dubbo-monitor IN A 60 10.9.7.10
```



### 准备k8s资源配置清单

运维主机`HDSS7-200.host.com`上

- [Deployment](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#dubbo-monitor-1)
- [Service](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#dubbo-monitor-2)
- [Ingress](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#dubbo-monitor-3)

vi /data/k8s-yaml/dubbo-monitor/deployment.yaml

复制

```
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: dubbo-monitor
  namespace: infra
  labels: 
    name: dubbo-monitor
spec:
  replicas: 1
  selector:
    matchLabels: 
      name: dubbo-monitor
  template:
    metadata:
      labels: 
        app: dubbo-monitor
        name: dubbo-monitor
    spec:
      containers:
      - name: dubbo-monitor
        image: harbor.od.com/infra/dubbo-monitor:latest
        ports:
        - containerPort: 8080
          protocol: TCP
        - containerPort: 20880
          protocol: TCP
        imagePullPolicy: IfNotPresent
      imagePullSecrets:
      - name: harbor
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      securityContext: 
        runAsUser: 0
      schedulerName: default-scheduler
  strategy:
    type: RollingUpdate
    rollingUpdate: 
      maxUnavailable: 1
      maxSurge: 1
  revisionHistoryLimit: 7
  progressDeadlineSeconds: 600
```



### 应用资源配置清单

在任意一台k8s运算节点执行：

复制

```
[root@hdss7-21 ~]# kubectl apply -f http://k8s-yaml.od.com/dubbo-monitor/deployment.yaml
deployment.extensions/dubbo-monitor created
[root@hdss7-21 ~]# kubectl apply -f http://k8s-yaml.od.com/dubbo-monitor/svc.yaml
service/dubbo-monitor created
[root@hdss7-21 ~]# kubectl apply -f http://k8s-yaml.od.com/dubbo-monitor/ingress.yaml
ingress.extensions/dubbo-monitor created
```



### 浏览器访问

[http://dubbo-monitor.od.com](http://dubbo-monitor.od.com/)

## dubbo服务消费者（dubbo-demo-consumer）

### 通过jenkins进行一次CI

打开jenkins页面，使用admin登录，准备构建`dubbo-demo`项目

![jenkins构建](https://blog.stanley.wang/images/jenkins-firstbuild.png)
点`Build with Parameters`

![jenkins构建详情](https://blog.stanley.wang/images/jenkins-builddetail.png)
依次填入/选择：

- app_name

  > dubbo-demo-consumer

- image_name

  > app/dubbo-demo-consumer

- git_repo

  > [git@gitee.com](mailto:git@gitee.com):stanleywang/dubbo-demo-web.git

- git_ver

  > master

- add_tag

  > 190117_1950

- mvn_dir

  > /

- target_dir

  > ./dubbo-client/target

- mvn_cmd

  > mvn clean package -Dmaven.test.skip=true

- base_image

  > base/jre8:8u112

- maven

  > 3.6.0-8u181

点击`Build`进行构建，等待构建完成。

test $? -eq 0 && 成功，进行下一步 || 失败，排错直到成功

### 检查harbor仓库内镜像

![harbor仓库内镜像](https://blog.stanley.wang/images/harbor-secondci.png)

### 解析域名

在DNS主机`HDSS7-11.host.com`上：

复制

```
/var/named/od.com.zone
demo IN A 60 10.9.7.10
```



### 准备k8s资源配置清单

运维主机`HDSS7-200.host.com`上，准备资源配置清单

- [Deployment](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#dubbo-demo-consumer-1)
- [Service](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#dubbo-demo-consumer-2)
- [Ingress](https://blog.stanley.wang/2019/01/18/实验文档2：实战交付一套dubbo微服务到kubernetes集群/#dubbo-demo-consumer-3)

vi /data/k8s-yaml/dubbo-demo-consumer/deployment.yaml

复制

```
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: dubbo-demo-consumer
  namespace: app
  labels: 
    name: dubbo-demo-consumer
spec:
  replicas: 1
  selector:
    matchLabels: 
      name: dubbo-demo-consumer
  template:
    metadata:
      labels: 
        app: dubbo-demo-consumer
        name: dubbo-demo-consumer
    spec:
      containers:
      - name: dubbo-demo-consumer
        image: harbor.od.com/app/dubbo-demo-consumer:master_190119_2015
        ports:
        - containerPort: 8080
          protocol: TCP
        - containerPort: 20880
          protocol: TCP
        env:
        - name: JAR_BALL
          value: dubbo-client.jar
        imagePullPolicy: IfNotPresent
      imagePullSecrets:
      - name: harbor
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      securityContext: 
        runAsUser: 0
      schedulerName: default-scheduler
  strategy:
    type: RollingUpdate
    rollingUpdate: 
      maxUnavailable: 1
      maxSurge: 1
  revisionHistoryLimit: 7
  progressDeadlineSeconds: 600
```



### 应用资源配置清单

在任意一台k8s运算节点执行：

复制

```
[root@hdss7-21 ~]# kubectl apply -f http://k8s-yaml.od.com/dubbo-demo-consumer/deployment.yaml
deployment.extensions/dubbo-demo-consumer created
[root@hdss7-21 ~]# kubectl apply -f http://k8s-yaml.od.com/dubbo-demo-consumer/svc.yaml
service/dubbo-demo-consumer created
[root@hdss7-21 ~]# kubectl apply -f http://k8s-yaml.od.com/dubbo-demo-consumer/ingress.yaml
ingress.extensions/dubbo-demo-consumer created
```



### 检查docker运行情况及dubbo-monitor

[http://dubbo-monitor.od.com](http://dubbo-monitor.od.com/)

### 浏览器访问

http://demo.od.com/hello?name=wangdao

# 实战维护dubbo微服务集群

## 更新（rolling update）

- 修改代码提git（发版）

- 使用jenkins进行CI

- 修改并应用k8s资源配置清单

  > 或者在k8s的dashboard上直接操作

## 扩容（scaling）

- k8s的dashboard上直接操作