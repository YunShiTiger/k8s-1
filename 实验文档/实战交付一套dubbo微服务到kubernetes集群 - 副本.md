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
mkdir -p /data/software/dockerfile/jenkins
cd /data/software/dockerfile/jenkins
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
yum install -y docker-ce-18.06.3.ce-3.el7
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

```bash
mkdir  -p /data/software/yaml/jenkins 
mkdir -p /data/nfs-volume/jenkins_home
cd /data/software/yaml/jenkins
```

deployment

```yaml
cat << EOF >deployment.yaml
kind: Deployment
apiVersion: apps/v1
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
          server: 10.0.0.20
          path: /data/nfs-volume/jenkins_home
      - name: docker
        hostPath: 
          path: /run/docker.sock
          type: ''
      containers:
      - name: jenkins
        image: harbor.wzxmt.com/infra/jenkins:v2.195
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
      - name: harborlogin
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
EOF
```

svc

```yaml
cat << EOF >svc.yaml
kind: Service
apiVersion: v1
metadata: 
  name: jenkins
  namespace: infra
spec:
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  selector:
    app: jenkins
  type: ClusterIP
  sessionAffinity: None
EOF
```

ingress

```yaml
cat << EOF >ingress.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:  
  name: jenkins
  namespace: infra
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:  
  rules:    
    - host: jenkins.wzxmt.com      
      http:        
        paths:        
        - path: /          
          backend:            
            serviceName: jenkins            
            servicePort: 80
EOF
```

## 应用资源配置清单

创建docker-registry

```bash
kubectl create secret docker-registry harborlogin \
--namespace=infra  \
--docker-server=https://harbor.wzxmt.com \
--docker-username=admin \
--docker-password=admin
```

任意一个k8s运算节点上

```bash
kubectl create namespace infra
kubectl apply -f  http://www.wzxmt.com/yaml/jenkins/deployment.yaml
kubectl apply -f  http://www.wzxmt.com/yaml/jenkins/svc.yaml
kubectl apply -f  http://www.wzxmt.com/yaml/jenkins/ingress.yaml

kubectl get pods -n infra|grep jenkins
kubectl get svc -n infra|grep jenkins
kubectl get ingress -n infra|grep jenkins
```

## 解析域名

`HDSS7-11.host.com`上

复制

```
jenkins	60 IN A 10.0.0.50
```

## 浏览器访问

[http://jenkins.wzxmt.com](http://jenkins.wzxmt.com/)

## 优化jenkins插件下载速度

在管理机上

```bash
WORK_DIR=/data/nfs-volume/jenkins_home/
sed -i.bak 's#http://updates.jenkins-ci.org/download#https://mirrors.tuna.tsinghua.edu.cn/jenkins#g;s#http://www.google.com#https://www.baidu.com#g' ${WORK_DIR}/updates/default.json
```

从新在运算节点部署jenkins

```bash
kubectl delete -f  http://www.wzxmt.com/yaml/jenkins/deployment.yaml
kubectl apply -f  http://www.wzxmt.com/yaml/jenkins/deployment.yaml
```

## 页面配置jenkins

![jenkins初始化页面](../upload/image-20200524143150587.png)

### 初始化密码

```
cat /data/nfs-volume/jenkins_home/secrets/initialAdminPassword
```

### 安装插件

![jenkins安装页面](../upload/image-20200524143444194.png)

### 设置用户

![jenkins设置用户](../upload/image-20200524161048685.png)

### 完成安装

![jenkins完成安装1](../upload/image-20200524161225578.png)
![jenkins完成安装2](../upload/image-20200524161328386.png)

### 使用admin登录

![jenkins登录](../upload/jenkins-welcome.png)

### 安装Blue Ocean插件

- Manage Jenkins
- Manage Plugins
- Available
- Blue Ocean

### 调整安全选项

- Manage Jenkins
  - Configure Global Security
    - Allow anonymous read access（钩上）

- Manage Jenkins
  - 防止跨站点请求伪造(取消钩)

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
   > Description : project git repository. e.g: https://github.com/wzxmt/dubbo-demo-service.git

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

![image-20200524230105011](https://raw.githubusercontent.com/wzxmt/images/master/img/image-20200524230105011.png)

## Pipeline Script

```yaml
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
          writeFile file: "${params.app_name}/${env.BUILD_NUMBER}/Dockerfile", text: """FROM harbor.wzxmt.com/${params.base_image}
ADD ${params.target_dir}/project_dir /opt/project_dir"""
          sh "cd  ${params.app_name}/${env.BUILD_NUMBER} && docker build -t harbor.wzxmt.com/${params.image_name}:${params.git_ver}_${params.add_tag} . && docker push harbor.wzxmt.com/${params.image_name}:${params.git_ver}_${params.add_tag} && docker rmi harbor.wzxmt.com/${params.image_name}:${params.git_ver}_${params.add_tag}"
        }
      }
   }
}
```

# 最后的准备工作

## 检查jenkins容器里的docker客户端

进入jenkins的docker容器里，检查docker客户端是否可用。

```bash
docker exec -ti 52e250789b78 bash
docker ps -a
```

## 检查jenkins容器里的SSH key

进入jenkins的docker容器里，检查ssh连接git仓库，确认是否能拉到代码。

```bash
docker exec -ti 52e250789b78 bash
ssh -i /root/.ssh/id_rsa -T git@github.com (有可能失败，但是只要能拉到代码)                                       
```

## 部署maven软件

[maven官方下载地址](http://maven.apache.org/docs/history.html)
在运维主机上二进制部署，这里部署maven-3.6.3版

```bash
tar xf /data/software/sf/apache-maven-3.6.3-bin.tar.gz -C /data/nfs-volume/jenkins_home
mv /data/nfs-volume/jenkins_home/apache-maven-3.6.3 /data/nfs-volume/jenkins_home/maven-3.6.3-8u222
```

设置国内镜像源

```bash
vim /data/nfs-volume/jenkins_home/maven-3.6.3-8u222/conf/settings.xml
  <mirror>
    <id>alimaven</id>
    <name>aliyun maven</name>
    <url>http://maven.aliyun.com/nexus/content/groups/public/</url>
    <mirrorOf>central</mirrorOf>
  </mirror>  
</mirrors>
<!-- profiles
#注意位置
```

其他版本略

## 制作dubbo微服务的底包镜像

运维主机上

1. 自定义Dockerfile

```bash
mkdir -p /data/software/dockerfile/jre8
cd /data/software/dockerfile/jre8
cat << EOF >Dockerfile
FROM stanleyws/jre8:8u112
RUN /bin/cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&\
    echo 'Asia/Shanghai' >/etc/timezone
ADD config.yml /opt/prom/config.yml
ADD jmx_javaagent-0.3.1.jar /opt/prom/
WORKDIR /opt/project_dir
ADD entrypoint.sh /entrypoint.sh
CMD ["/entrypoint.sh"]
EOF
```

config.yml

```bash
cat << 'EOF' >config.yml
---
rules:
  - pattern: '.*'
EOF
```

jmx_javaagent-0.3.1.jar

```bash
wget https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.3.1/jmx_prometheus_javaagent-0.3.1.jar -O jmx_javaagent-0.3.1.jar
```

entrypoint.sh

```bash
cat << 'EOF' >entrypoint.sh
#!/bin/sh
M_OPTS="-Duser.timezone=Asia/Shanghai -javaagent:/opt/prom/jmx_javaagent-0.3.1.jar=$(hostname -i):${M_PORT:-"12346"}:/opt/prom/config.yml"
C_OPTS=${C_OPTS}
JAR_BALL=${JAR_BALL}
exec java -jar ${M_OPTS} ${C_OPTS} ${JAR_BALL}
EOF
chmod +x entrypoint.sh
```

制作dubbo服务docker底包

```bash
docker build . -t harbor.wzxmt.com/base/jre8:8u112
docker push harbor.wzxmt.com/base/jre8:8u112
```

**注意：**jre7底包制作类似，这里略

# 交付dubbo微服务至kubernetes集群

## dubbo服务提供者（dubbo-demo-service）

### 通过jenkins进行一次CI

打开jenkins页面，使用admin登录，准备构建`dubbo-demo`项目

![jenkins构建](https://raw.githubusercontent.com/wzxmt/images/master/img/image-20200524231817369.png)
点`Build with Parameters`

![jenkins构建详情](https://blog.stanley.wang/images/jenkins-builddetail.png)
依次填入/选择：

- app_name

  > dubbo-demo-service

- image_name

  > app/dubbo-demo-service

- git_repo

  > https://github.com/wzxmt/dubbo-demo-service.git

- git_ver

  > master

- add_tag

  > 200525_0100

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

运维主机上，准备资源配置清单：

```yaml
cat << 'EOF' >/data/software/yaml/dubbo-demo-service/deployment.yaml
kind: Deployment
apiVersion: apps/v1
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
        image: harbor.wzxmt.com/app/dubbo-demo-service:master_200526_2355
        ports:
        - containerPort: 20880
          protocol: TCP
        env:
        - name: JAR_BALL
          value: dubbo-server.jar
        imagePullPolicy: IfNotPresent
      imagePullSecrets:
      - name: harborlogin
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
EOF
```

### 应用资源配置清单

在任意一台k8s运算节点执行：

```bash
kubectl create ns app

kubectl create secret docker-registry harborlogin \
--namespace=app  \
--docker-server=https://harbor.wzxmt.com \
--docker-username=admin \
--docker-password=admin

kubectl apply -f http://www.wzxmt.com/yaml/dubbo-demo-service/deployment.yaml
```

### 检查docker运行情况及zk里的信息

```bash
/opt/zookeeper/zookeeper/bin/zkCli.sh 
#打开另外一个zookeeper
/opt/zookeeper/bin/zkCli.sh -server localhost
[zk: localhost(CONNECTED) 0] ls /dubbo
[com.od.dubbotest.api.HelloService]
```

## dubbo-monitor工具

[dubbo-monitor源码包](https://github.com/alibaba/dubbo/archive/dubbo-2.6.0.zip)

#### 下载源码

```bash
wget https://github.com/alibaba/dubbo/archive/dubbo-2.6.0.zip
unzip dubbo-2.6.0.zip && cd dubbo-dubbo-2.6.0/dubbo-simple/dubbo-monitor-simple
```

安装依赖，编译dubbo-monitor

```bash
yum -y install java-1.8.0-openjdk maven
mvn clean install
```

编译成功后的目标文件为：target/dubbo-monitor-simple-2.6.0-assembly.tar.gz

解压

```bash
mkdir -p /data/software/dockerfile/dubbo-monitor
tar xf target/dubbo-monitor-simple-2.6.0-assembly.tar.gz
mv dubbo-monitor-simple-2.6.0 /data/software/dockerfile/dubbo-monitor/dubbo-monitor-simple
```

修改配置

```bash
cd /data/software/dockerfile/dubbo-monitor
cat << EOF >dubbo-monitor-simple/conf/dubbo.properties
dubbo.container=log4j,spring,registry,jetty
dubbo.application.name=monitor
dubbo.application.owner=wzxmt
dubbo.registry.address=zookeeper://zk1.wzxmt.com:2181?backup=zk2.wzxmt.com:2181,zk3.wzxmt.com:2181
dubbo.protocol.port=20880
dubbo.jetty.port=8080
dubbo.jetty.directory=/dubbo-monitor-simple/monitor
dubbo.charts.directory=/dubbo-monitor-simple/charts
dubbo.statistics.directory=/dubbo-monitor-simple/monitor/statistics
dubbo.log4j.file=logs/dubbo-monitor-simple.log
dubbo.log4j.level=WARN
EOF
```

#### 制作镜像

1. 准备环境

   修改启动初始化内存

   ```bash
   chmod +x dubbo-monitor-simple/bin/*
   sed -i "s#128m#16m#g;s#256m#32m#g;s#1g#128m#g;s#2g#256m#g" dubbo-monitor-simple/bin/start.sh
   sed -i '69,$d' dubbo-monitor-simple/bin/start.sh
   echo 'exec java $JAVA_OPTS $JAVA_MEM_OPTS $JAVA_DEBUG_OPTS $JAVA_JMX_OPTS -classpath $CONF_DIR:$LIB_JARS com.alibaba.dubbo.container.Main &> $STDOUT_FILE' >>dubbo-monitor-simple/bin/start.sh
   ```
   
2. 准备Dockerfile

   ```bash
   \cp /usr/share/zoneinfo/Asia/Shanghai ./
   cat << EOF >Dockerfile
   FROM jeromefromcn/docker-alpine-java-bash
   MAINTAINER Jerome Jiang
   WORKDIR /dubbo-monitor-simple
   ADD Shanghai /etc/localtime
   COPY dubbo-monitor-simple/ /dubbo-monitor-simple/
   CMD bin/start.sh
   EOF
   ```

3. build镜像

   ```bash
   docker build . -t harbor.wzxmt.com/infra/dubbo-monitor:latest
   docker push harbor.wzxmt.com/infra/dubbo-monitor:latest
   ```

### 解析域名

```bash
dubbo-monitor IN A 60 10.0.0.50
```

### 准备k8s资源配置清单

运维主机上

deployment

```yaml
mkdir /data/software/yaml/dubbo-monitor -p
cd /data/software/yaml/dubbo-monitor
cat << EOF >dp.yaml
kind: Deployment
apiVersion: apps/v1
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
        image: harbor.wzxmt.com/infra/dubbo-monitor:latest
        ports:
        - containerPort: 8080
          protocol: TCP
        - containerPort: 20880
          protocol: TCP
        imagePullPolicy: IfNotPresent
      imagePullSecrets:
      - name: harborlogin
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
EOF
```

Service

```yaml
cat << EOF >svc.yaml
kind: Service
apiVersion: v1
metadata: 
  name: dubbo-monitor
  namespace: infra
spec:
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
  selector: 
    app: dubbo-monitor
  clusterIP: None
  type: ClusterIP
  sessionAffinity: None
EOF
```

ingress

```yaml
cat << EOF >ingress.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:  
  name: dubbo-monitor
  namespace: infra
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:  
  rules:    
    - host: dubbo-monitor.wzxmt.com      
      http:        
        paths:        
        - path: /          
          backend:            
            serviceName: dubbo-monitor            
            servicePort: 80
EOF
```

### 应用资源配置清单

在任意一台k8s运算节点执行：

```bash
kubectl apply -f http://www.wzxmt.com/yaml/dubbo-monitor/dp.yaml
kubectl apply -f http://www.wzxmt.com/yaml/dubbo-monitor/svc.yaml
kubectl apply -f http://www.wzxmt.com/yaml/dubbo-monitor/ingress.yaml
```

### 浏览器访问

http://dubbo-monitor.wzxmt.com

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

  > https://github.com/wzxmt/dubbo-demo-web.git

- git_ver

  > master

- add_tag

  > 200527_2150

- mvn_dir

  > ./

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

```bash
demo IN A 60 10.0.0.50
```

### 准备k8s资源配置清单

运维主机准备资源配置清单

deployment

```yaml
mkdir -p /data/software/yaml/dubbo-demo-consumer
cd /data/software/yaml/dubbo-demo-consumer
cat << EOF >dp.yaml
kind: Deployment
apiVersion: apps/v1
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
        image: harbor.wzxmt.com/app/dubbo-demo-consumer:master_200527_2150
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
      - name: harborlogin
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
EOF
```

Service

```yaml
cat << EOF >svc.yaml
kind: Service
apiVersion: v1
metadata: 
  name: dubbo-demo-consumer
  namespace: app
spec:
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
  selector: 
    app: dubbo-demo-consumer
  clusterIP: None
  type: ClusterIP
  sessionAffinity: None
EOF
```

ingress

```yaml
cat << EOF >ingress.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:  
  name: dubbo-demo-consumer
  namespace: app
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:  
  rules:    
    - host: demo.wzxmt.com      
      http:        
        paths:        
        - path: /          
          backend:            
            serviceName: dubbo-demo-consumer            
            servicePort: 8080
EOF
```

### 应用资源配置清单

在任意一台k8s运算节点执行：

```bash
kubectl apply -f http://www.wzxmt.com/yaml/dubbo-demo-consumer/dp.yaml
kubectl apply -f http://www.wzxmt.com/yaml/dubbo-demo-consumer/svc.yaml
kubectl apply -f http://www.wzxmt.com/yaml/dubbo-demo-consumer/ingress.yaml
```

### 检查dubbo-monitor

http://dubbo-monitor.wzxmt.com

### 浏览器访问

http://demo.wzxmt.com/hello?name=wangdao

# 实战维护dubbo微服务集群

## 更新（rolling update）

- 修改代码提git（发版）

- 使用jenkins进行CI

- 修改并应用k8s资源配置清单

  > 或者在k8s的dashboard上直接操作

## 扩容（scaling）

- k8s的dashboard上直接操作