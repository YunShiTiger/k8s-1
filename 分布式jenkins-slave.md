# 简介

我们知道持续构建与发布是我们日常工作中必不可少的一个步骤，目前大多公司都采用 Jenkins 集群来搭建符合需求的 CI/CD 流程，然而传统的 Jenkins Slave 一主多从方式会存在一些痛点，比如：

- 主 Master 发生单点故障时，整个流程都不可用了
- 每个 Slave 的配置环境不一样，来完成不同语言的编译打包等操作，但是这些差异化的配置导致管理起来非常不方便，维护起来也是比较费劲
- 资源分配不均衡，有的 Slave 要运行的 job 出现排队等待，而有的 Slave 处于空闲状态
- 资源有浪费，每台 Slave 可能是物理机或者虚拟机，当 Slave 处于空闲状态时，也不会完全释放掉资源。

正因为上面的这些种种痛点，我们渴望一种更高效更可靠的方式来完成这个 CI/CD 流程，而 Docker 虚拟化容器技术能很好的解决这个痛点，又特别是在 Kubernetes 集群环境下面能够更好来解决上面的问题，下图是基于 Kubernetes 搭建 Jenkins 集群的简单示意图：![k8s-jenkins](https://raw.githubusercontent.com/wzxmt/images/master/img/k8s-jenkins-slave.png)

从图上可以看到 Jenkins Master 和 Jenkins Slave 以 Pod 形式运行在 Kubernetes 集群的 Node 上，Master 运行在其中一个节点，并且将其配置数据存储到一个 Volume 上去，Slave 运行在各个节点上，并且它不是一直处于运行状态，它会按照需求动态的创建并自动删除。

这种方式的工作流程大致为：当 Jenkins Master 接受到 Build 请求时，会根据配置的 Label 动态创建一个运行在 Pod 中的 Jenkins Slave 并注册到 Master 上，当运行完 Job 后，这个 Slave 会被注销并且这个 Pod 也会自动删除，恢复到最初状态。

那么我们使用这种方式带来了哪些好处呢？

- **服务高可用**，当 Jenkins Master 出现故障时，Kubernetes 会自动创建一个新的 Jenkins Master 容器，并且将 Volume 分配给新创建的容器，保证数据不丢失，从而达到集群服务高可用。
- **动态伸缩**，合理使用资源，每次运行 Job 时，会自动创建一个 Jenkins Slave，Job 完成后，Slave 自动注销并删除容器，资源自动释放，而且 Kubernetes 会根据每个资源的使用情况，动态分配 Slave 到空闲的节点上创建，降低出现因某节点资源利用率高，还排队等待在该节点的情况。
- **扩展性好**，当 Kubernetes 集群的资源严重不足而导致 Job 排队等待时，可以很容易的添加一个 Kubernetes Node 到集群中，从而实现扩展。

是不是以前我们面临的种种问题在 Kubernetes 集群环境下面是不是都没有了啊？看上去非常完美。

## 部署jenkins-master

#### 获取镜像

> [jenkins官网](https://jenkins.io/download/)
> [jenkins镜像](https://hub.docker.com/r/jenkins/jenkins)

在运维主机下载官网上的稳定版

```bash
docker pull jenkins/jenkins:2.195-centos
docker tag jenkins/jenkins:2.195-centos harbor.wzxmt.com/infra/jenkins:v2.195
docker push harbor.wzxmt.com/infra/jenkins:v2.195
```

#### 准备共享存储

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

#### 准备资源配置清单

RBAC

```bash
cat << 'EOF' >rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins
  namespace: infra
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: jenkins
rules:
  - apiGroups: ["extensions", "apps"]
    resources: ["deployments"]
    verbs: ["create", "delete", "get", "list", "watch", "patch", "update"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["create", "delete", "get", "list", "watch", "patch", "update"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create","delete","get","list","patch","update","watch"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create","delete","get","list","patch","update","watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get","list","watch"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: jenkins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: jenkins
subjects:
  - kind: ServiceAccount
    name: jenkins
    namespace: infra
EOF
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
      serviceAccountName: jenkins
      containers:
      - name: jenkins
        image: harbor.wzxmt.com/infra/jenkins:v2.195
        ports:
        - containerPort: 8080
          protocol: TCP
        - containerPort: 50000
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
  - name: web
    port: 80
    targetPort: 8080
  - name: agent 
    port: 50000
    targetPort: 50000  
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

创建docker-registry

```bash
kubectl create secret docker-registry harborlogin \
--namespace=infra  \
--docker-server=http://harbor.wzxmt.com \
--docker-username=admin \
--docker-password=admin
```

#### 应用资源清单

```bash
kubectl create namespace infra
kubectl apply -f ./
```

#### 解析域名

```
jenkins	60 IN A 10.0.0.50
```

#### 浏览器访问

[http://jenkins.wzxmt.com](http://jenkins.wzxmt.com/)

#### 优化jenkins插件下载速度

在管理机上

```bash
WORK_DIR=/data/nfs-volume/jenkins_home
sed -i.bak 's#http://updates.jenkins-ci.org/download#https://mirrors.tuna.tsinghua.edu.cn/jenkins#g;s#http://www.google.com#https://www.baidu.com#g' ${WORK_DIR}/updates/default.json
```

从新在运算节点部署jenkins

```bash
kubectl delete -f  deployment.yaml
kubectl apply -f  deployment.yaml
```

#### 页面配置jenkins

等到服务启动成功后，我们就可以通过[http://jenkins.wzxmt.com](http://jenkins.wzxmt.com/)访问 jenkins 服务了，可以根据提示信息进行安装配置即可：![setup jenkins](https://raw.githubusercontent.com/wzxmt/images/master/img/image-20200622074600136.png)初始化的密码我们可以在 jenkins 的容器的日志中进行查看，也可以直接在 nfs 的共享数据目录中查看：

```shell
$ cat ${WORK_DIR}/secrets/initialAdminPassword
```

然后选择安装推荐的插件即可。![setup plugin](https://raw.githubusercontent.com/wzxmt/images/master/img/image-20200622074852477.png)   

安装完成后添加管理员帐号即可进入到 jenkins 主界面：![jenkins home](https://raw.githubusercontent.com/wzxmt/images/master/img/image-20200622075706388.png)

#### 配置

接下来我们就需要来配置 Jenkins，让他能够动态的生成 Slave 的 Pod。

**第1步.** 我们需要安装**kubernetes plugin (新版本就叫 Kubernetes)**， 点击 Manage Jenkins -> Manage Plugins -> Available -> Kubernetes plugin 勾选安装即可。

![image-2020062](https://raw.githubusercontent.com/wzxmt/images/master/img/image-2020062208044.png)

**第2步.** 安装完毕后，点击 Manage Jenkins —> Configure System —> (拖到最下方)Add a new cloud —> 选择 Kubernetes，然后填写 Kubernetes 和 Jenkins 配置信息。![image-20200622094452898](https://raw.githubusercontent.com/wzxmt/images/master/img/image-20200627224756024.png)

## 部署jenkins-slave

#### jenkins-slave dockerfile结构

```
├── Dockerfile（见下面）
├── settings.xml（maven配置文件）
├── helm（helm包管理器）
├── apache-maven-3.6.3-bin.tar.gz（maven工具）
├── config（连接api-serviservice信息）
├── config.json（连接harbor信息）
└── id_rsa （连接git）
```

#### 下载maven

```bash
wget https://mirrors.bfsu.edu.cn/apache/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz
```

#### 下载helm

```bash
wget https://get.helm.sh/helm-v3.2.4-linux-amd64.tar.gz
```

#### 生成ssh密钥对：

```bash
ssh-keygen -t rsa -b 2048 -C "wzxmt.com@qq.com" -N "" -f /root/.ssh/id_rsa
cp /root/.ssh/id_rsa ./
```

#### 编写dockerfile

```bash
cat << 'EOF' >Dockerfile
ARG version=4.3-4
FROM jenkins/inbound-agent:$version
USER root
COPY * /root/
RUN mkdir /root/.kube &&  mkdir -p /root/.ssh && mkdir /root/.docker && cd /root/ && chown -R root. /root/ && \
mv id_rsa /root/.ssh/id_rsa && mv config /root/.kube/config && mv config.json /root/.docker/config.json && \
mv kubectl /usr/local/bin/kubectl && tar xf apache-maven-3.6.3-bin.tar.gz && \
mv apache-maven-3.6.3 /opt/maven-3.6.3 && \mv settings.xml /opt/maven-3.6.3/conf/settings.xml && \
tar xf helm-v3.2.4-linux-amd64.tar.gz && mv linux-amd64/helm /usr/local/bin/ && rm -f *.gz
ENTRYPOINT ["jenkins-agent"]
EOF
```

#### 构建镜像

```bash
docker build . -t harbor.wzxmt.com/infra/jenkins-slave:v4.3-4
docker push harbor.wzxmt.com/infra/jenkins-slave:v4.3-4
```

pipline

```yaml
pipeline {
  agent {
    kubernetes {
      yaml """
apiVersion: v1
kind: Pod
metadata:
  name: jenkins-slave
spec:
  nodeName: n2
  containers:
  - name: jnlp
    image: harbor.wzxmt.com/infra/jenkins-slave:v4.3-4
    tty: true
    imagePullPolicy: Always
    volumeMounts:
      - name: docker-cmd
        mountPath: /usr/bin/docker
      - name: docker-socker
        mountPath: /run/docker.sock
      - name: date
        mountPath: /etc/localtime
      - name: maven-cache
        mountPath: /root/.m2
  restartPolicy: Never
  imagePullSecrets:
    - name: harborlogin
  volumes:
    - name: date
      hostPath: 
        path: /etc/localtime
        type: ''
    - name: docker-cmd
      hostPath: 
        path: /usr/bin/docker
        type: ''
    - name: docker-socker
      hostPath: 
        path: /run/docker.sock
        type: ''
    - name: maven-cache
      nfs: 
        server: 10.0.0.20
        path: /data/nfs-volume/maven-cache
"""
   }
}
   stages {
      stage('kubectl') {
         steps {
            sh 'kubectl get pod -A'
         }
      }
      stage('maven') {
         steps {
            sh '/opt/maven-3.6.3/bin/mvn -version'
         }
      }
      stage('docker') {
         steps {
            sh 'docker images'
         }
      }
      stage('date') {
         steps {
            sh 'date'
         }
      }
       stage('helm') {
         steps {
            sh 'pwd'
         }
      }
   }
}
```



## test

### 新建Jenkins的pipeline

### 配置New job

- 使用admin登录

- New Item

- create new jobs

- Enter an item name

  > tomcat-demo

- Pipeline -> OK

- Discard old builds

  > Days to keep builds : 3
  > Max # of builds to keep : 30

- This project is parameterized

1. Add Parameter -> String Parameter

   > Name : app_name
   > Default Value :
   > Description : project name. e.g: dubbo-demo-web

2. Add Parameter -> String Parameter

   > Name : image_name
   > Default Value :
   > Description : project docker image name. e.g: app/dubbo-demo-web

3. Add Parameter -> String Parameter

   > Name : git_repo
   > Default Value :
   > Description : project git repository. e.g: [git@gitee.com](https://gitee.com/wzxmt/dubbo-demo-web.git)

4. Add Parameter -> String Parameter

   > Name : git_ver
   > Default Value : tomcat
   > Description : git commit id of the project.

5. Add Parameter -> String Parameter

   > Name : add_tag
   > Default Value :
   > Description : project docker image tag, date_timestamp recommended. e.g: 200607_0930

6. Add Parameter -> String Parameter

   > Name : mvn_dir
   > Default Value :  /opt
   > Description : project maven directory. e.g: /opt

7. Add Parameter -> String Parameter

   > Name : target_dir
   > Default Value : ./dubbo-client/target
   > Description : the relative path of target file such as .jar or .war package. e.g: ./dubbo-client/target

8. Add Parameter -> String Parameter

   > Name : mvn_cmd
   > Default Value : mvn clean package -Dmaven.test.skip=true
   > Description : maven command. e.g: mvn clean package -e -q -Dmaven.test.skip=true

9. Add Parameter -> Choice Parameter

   > Name : base_image
   > Default Value :
   >
   > - k/tomcat:v7.0.94
   > - base/tomcat:v8.5.40
   > - base/tomcat:v9.0.17
   >   Description : project base image list in harbor.wzxmt.com.

10. Add Parameter -> Choice Parameter

    > Name : maven
    > Default Value :
    >
    > - maven-3.6.0
    > - maven-3.6.3
    >   Description : different maven edition.

11. Add Parameter -> String Parameter

    > Name : root_url
    > Default Value : ROOT
    > Description : webapp dir.

### Pipeline Script

```yaml
pipeline {
  agent {
    kubernetes {
      yaml """
apiVersion: v1
kind: Pod
metadata:
  name: jenkins-slave
spec:
  nodeName: n2
  containers:
  - name: jnlp
    image: harbor.wzxmt.com/infra/jenkins-slave:v4.3-4
    tty: true
    imagePullPolicy: Always
    volumeMounts:
      - name: docker-cmd
        mountPath: /usr/bin/docker
      - name: docker-socker
        mountPath: /run/docker.sock
      - name: date
        mountPath: /etc/localtime
      - name: maven-cache
        mountPath: /root/.m2
  restartPolicy: Never
  imagePullSecrets:
    - name: harborlogin
  volumes:
    - name: date
      hostPath: 
        path: /etc/localtime
        type: ''
    - name: docker-cmd
      hostPath: 
        path: /usr/bin/docker
        type: ''
    - name: docker-socker
      hostPath: 
        path: /run/docker.sock
        type: ''
    - name: maven-cache
      nfs: 
        server: 10.0.0.20
        path: /data/nfs-volume/maven-cache
"""
   }
} 
    stages {
    stage('pull') { //get project code from repo 
      steps {
        sh "git clone ${params.git_repo} ${params.app_name}/${env.BUILD_NUMBER} && cd ${params.app_name}/${env.BUILD_NUMBER} && git checkout ${params.git_ver}"
        }
    }
    stage('build') { //exec mvn cmd
      steps {
        sh "cd ${params.app_name}/${env.BUILD_NUMBER} && ${params.mvn_dir}/${params.maven}/bin/${params.mvn_cmd}"
      }
    }
    stage('unzip') { //unzip  target/*.war -c target/project_dir
      steps {
        sh "cd ${params.app_name}/${env.BUILD_NUMBER} && cd ${params.target_dir} && mkdir project_dir && unzip *.war -d ./project_dir"
      }
    }
    stage('image') { //build image and push to registry
      steps {
        writeFile file: "${params.app_name}/${env.BUILD_NUMBER}/Dockerfile", text: """FROM harbor.wzxmt.com/${params.base_image}
ADD ${params.target_dir}/project_dir /opt/tomcat/webapps/${params.root_url}"""
        sh "cd  ${params.app_name}/${env.BUILD_NUMBER} && \
        docker build -t harbor.wzxmt.com/${params.image_name}:${params.git_ver}_${params.add_tag} . && \
        docker push harbor.wzxmt.com/${params.image_name}:${params.git_ver}_${params.add_tag} && \
        docker rmi harbor.wzxmt.com/${params.image_name}:${params.git_ver}_${params.add_tag}"
      }
    }
  }
}
```

### 构建应用镜像

使用Jenkins进行CI，并查看harbor仓库
![jenkins构建](https://raw.githubusercontent.com/wzxmt/images/master/img/image-20200628020151780.png)

依次填入/选择：

- app_name

  > dubbo-demo-web

- image_name

  > app/dubbo-demo-web

- git_repo

  > https://gitee.com/wzxmt/dubbo-demo-web.git

- git_ver

  > tomcat

- add_tag

  > 200628_0140

- mvn_dir

  > /opt

- target_dir

  > ./dubbo-client/target

- mvn_cmd

  > mvn clean package -Dmaven.test.skip=true

- base_image

  > base/tomcat:v8.5.40

- maven

  > maven-3.6.3

- root_url

  >ROOT

### 开始构建

![image-20200628021513893](https://raw.githubusercontent.com/wzxmt/images/master/img/image-20200628021513893.png)

