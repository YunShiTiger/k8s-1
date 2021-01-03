随着Kubernetes和云原生加速企业产品落地，现在总结以下几点

- 更快的应用开发与交付
- 天然适合微服务，是微服务和Devops的桥梁
- 可移植性，支持公有云，私有云，裸机，虚拟机
- 标准化的应用开发与发布：声明式API和Operator
- 自动化运维：弹性伸缩（HPA），故障自愈，负载均衡，配置管理等

另外就是交付spring cloud到k8s之前说一下微服务的概念

## 一、什么是微服务？

早在2011年的5月份在威尼斯的一个架构研讨会上微服务的概念就被人提起了，当时的参会者对它的描述只是一种通用的软件并没给出明确的定义是什么，之后随着技术的不断发展，在2014年詹姆斯里维斯以及它的伙伴马丁福勒在它的微博中发表了一篇有关于微服务特点的文章，对微服务进行了全面的阐述，之后[微服务](https://martinfowler.com/articles/microservices.html)就走进了我们的视野;在这个文章中并给出微服务一个明确的定义，

微服务其实是一种软件的架构风格，是一种将单体架构拆分为小的服务进行去开发，每个服务都运行在自己的进程中，采用的是轻量级的restful或者http进行通信，并且都是独立开发独立部署和测试的，可以使用多种语言进行开发,对于微服务有一个关键点叫化整为零，把一个大的应用却成一个小的不同的应用;比如嘀嘀打车，早期在一个互联网应用上基本上都是单体架构，不是分布式,单体情况下把很多程序都写一个程序中，然后一台服务器对所有服务进行运行，但是随着并发的提高，这种单体架构显然承受不了了，这样的话就需要我们对我们软件的指责进行慢慢的划分，将其剥离出来，形成一个一个的微服务，也就是多个微服务的模块形成一个完整的应用，这些都是独立部署独立运行的，一个微服务也会运行在一个虚拟机里面。

### spring cloud微服务体系的组成

服务发现 （Eureka，Cousul，zookeeper）
		也就是注册中心最为微服务必不可少的中央管理者，服务发现的主要职责就是将其它的微服务模块进行登记与管理，这就相当于生活中来了一家公司，去工商局进行登记一样的道理，在服务发现中它主包含了三个子模块，分别是eureka，cousul，zookeeper，这些spring cloud底层都支持的注册中心，一般常用的是eureka和consul，微服务构建好后，那么微服务与微服务直接怎么进行服务直接的通信，或者微服务遇到了故障无法达到请求的（hystrix/ribbon/openfeign）
另外就是路由与过滤主要是针对对外接口的暴露的，这里主要涉及zuul，spring cloud gateway，这两个组件主要为外部的调用者比如其他的系统和我们的微服务进行通信的时候，由外到内是怎么彼此进行访问的，那么这些就是由这两个组件进行完成的。
		配置中心就是存放我们应用程序配置的地方，可能我们有上百个应用程序，那么每个应用程序都是一个微服务，那么就会产生一个很严重的问题，就是这些配置文件放在什么地方比如每个服务下都放一个xml，或者yml，维护起来是非常不方便的，因为改一个参数，就要对所有的应用进行调整，为了解决这个问题配置中心就出现了，相当于又提供了一个微服务把我们应用中所有的配置文件，都放在了配置中心中，那么其他应用都是通过配置中心来获取到这些配置文件的而不是我们要这个这个配置文件放到每个程序中，这样的好处就是可以将我们的配置文件进行集中的管理，只需要改一个地方所有地方都能生效

### spring cloud微服务组成

​		消息总线，spring cloud stream或者spring cloud bus就跟我们的消息mq差不多就是我们发布一个信息，到我们队列里面由其他的微服务或者其他的应用进行获取提供了系统与系统之间或者微服务与微服务之间的消息传递过程，这个中间增加了一个额外的东西叫做消息总线，具体的消息总线可以是mq或者是[Redis](https://www.linuxidc.com/topicnews.aspx?tid=22)，不同的厂商实现了不同的实现。
​		安全控制是针对我们安全的管理，在我们传统网站开发的时候，应用的访问控制有授权的可以使用这个功能，没有授权的就无法进行访问，安全控制在spring cloud中也是存在的提供了AUTH2.0方案的支持，链路监控就是对我们消息传递的过程要进行统筹和监控，比如系统中有10个微服务，而这10个微服务是彼此依赖的，第一个微服务它是底层最基础的用户管理而第二个微服务是基于用户管理开发一个权限管理，在往上是应用管理，应用系统的扩展，每一个微服务之间彼此之间进行依赖在顶层我们进行调用的时候会安装微服务的调用顺序一级一级消息往下传递，这样做有一个问题来了，如果中间有个环节出现了问题，没有响应服务我们在使用的角度当前我们的请求失败了，但是具体的环节不知道是在那一块出现问题，那么链路监控就是让我们快递定位消息传递过程哪个阶段进行出错，有助于我们问题的排查。
​		spring cloud cli命令行工具，来实现我们开发来实现的一些功能，spring cloud cluster是对我们集群管理的一个辅助工具

**现在去交付微服务到k8s中举个demo仅供参考**

```
一、发布流程设计
二、准备基础环境
三、在Kubernetes中部署jenkins
四、jenkins pipeline及参数化构建
五、jenkins在k8s中动态创建代理
六、自定义构建jenkins-slave镜像
七、基于kubernetes构建jenkins-ci系统
八、pipeline集成helm发布spring cloud微服务
```

![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281532.png)

## 二、传统的发布流程是怎么样的？

现在的这个发布流程设计还是要和自己的项目中去考量，布置一个大体的拓扑图，那么比如没有这样的场景jenkins去发布微服务，它是一个怎么样的流程，作为运维来讲首先要去拉代码，开发已经将这个项目开发好了，并推送到git仓库中或者部署的私有的gitlab代码仓库中，第一步做的就是将这个代码拉下来，拉完代码，一般代码都是[Java](https://www.linuxidc.com/Java)应用，会设计到一个编译，编译出来一个可部署的包，一般微服务是jar包，或者直接启动的应用程序，然后就开始去封装这个服务了，一般就是将这个jar包或者应用程序，通过dockerfile去达成一个可部署的镜像，这个镜像一般会自己制作jdk环境，或者就是jre环境，就是基础镜像能够运行这个镜像的底包，最后一步就是部署到k8s中，这里就会写一些yaml文件了去把这个镜像部署到k8s中，也就是容器的编排，另外还要考虑怎么将这个应用暴露出去，让用户访问到。

**使用jenkins自动话发布的流程是这么样的？**
显然这种方式发布多个微服务很不高效，所以就需要ci/cd，这么一说，那么有jenkins了，怎么将这种方式自动化起来，减少人工的干预。
上面那张图，首先是这样的，开发将代码推送到git仓库中，通过commit提交上去，然后再到jenkins了，它负责的任务就是checkout代码的拉取，code compile代码的编译，docker build &push ，镜像的构建与推送到harbor仓库中，然后deploy，将应用部署到k8s中，这里呢由于可能是很多的微服务，那么我们就需要模版的代替，去发布微服务，这里我们就会需要用到它原生的helm微服务发布工具来到k8s当中去deploy，发布到测试环境中去，然后通过slb提供一个统一的出口，发布出去，中间产生的镜像也都会存放到harbor仓库中，当QA测试没有问题，这个镜像也就可以去发布生产环境中。

**为什么需要jenkins slave架构**
另外这里还提到了一个jenkins，slave的一个架构，主要的是可以动态的可以完成这些任务，动态的去调度一个机器和一个pod来完成这几步的任务，因为当任务很多时，也就是都在jenkins master去做，显然任务多了负载就高了，所以就需要引入这个slave去解决这个问题。

## 三、准备基础环境，所需的组件来完成我们流程的发布

```
1、k8s——（ingress controller、coredns、pv自动供给）
2、harbor,并启用chart存储功能，将我们的helm打成chart并存放到harbor中
3、helm-v3 工具，主要来实现模版化，动态的将应用渲染安装与卸载，更好的去管理微服务
4、gitlab代码仓库，docker-compose实现
5、MySQL，微服务数据库
6、在k8s中部署eureka（注册中心）
```

1、检查k8s基础组件的环境是否安装：

- 默认我的这个基础的组件都是安装好的，ingress 和coredns

- k8s pv的自动供给，使用nfs或者Ceph持久化存储

2、部署镜像仓库Harbor（略）

3、helm-v3 工具

- 安装helm工具

- 安装push插件

- 推送与安装Chart，编写模板，推送至harbor仓库

4、部署gitlab（略）

5、部署

下载

```
git clone https://github.com/wzxmt/simple-microservice.git
cd simple-microservice-dev3
```

编译

```
mvn clean package -Dmaven.test.skip=true
```

Dockerfile

```bash
cat << 'EOF' >Dockerfile
FROM openjdk:8-jdk-alpine
LABEL maintainer www.wzxmt.com
ENV JAVA_ARGS="-Dfile.encoding=UTF8 -Duser.timezone=GMT+08"
COPY ./target/eureka-service.jar ./
EXPOSE 8888
CMD java -jar $JAVA_ARGS $JAVA_OPTS -Deureka.instance.hostname=${MY_POD_NAME}.eureka.ms /eureka-service.jar
EOF
```

构建镜像

```bash
docker build . -t harbor.wzxmt.com/infra/eureka:latest
docker push harbor.wzxmt.com/infra/eureka:latest
```

部署

```yaml
cat<< 'EOF' >eureka.yaml
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: eureka
  namespace: infra
spec:
  entryPoints:
    - web
  routes:
  - match: Host(`eureka.wzxmt.com`) && PathPrefix(`/`)
    kind: Rule
    services:
    - name: eureka
      port: 8888
---
apiVersion: v1
kind: Service
metadata:
  name: eureka
  namespace: infra
spec:
  clusterIP: None
  ports:
  - port: 8888
    name: eureka 
  selector:
    project: infra
    app: eureka

---

apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: eureka
  namespace: infra 
spec:
  replicas: 3
  selector:
    matchLabels:
      project: infra
      app: eureka
  serviceName: "eureka"
  template:
    metadata:
      labels:
        project: infra 
        app: eureka
    spec:
      imagePullSecrets:
      - name: harborlogin
      containers:
      - name: eureka
        image: harbor.wzxmt.com/infra/eureka:latest
        ports:
          - protocol: TCP
            containerPort: 8888
        env:
          - name: JAVA_OPTS
            value: "-Xmx1g"
          - name: MY_POD_NAME
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
        resources:
          requests:
            cpu: 0.5
            memory: 256Mi
          limits:
            cpu: 1 
            memory: 1Gi
        readinessProbe:
          tcpSocket:
            port: 8888
          initialDelaySeconds: 60
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: 8888
          initialDelaySeconds: 60
          periodSeconds: 10
EOF
```

5、mysql 微服务数据库 

创建数据库

```
cd simple-microservice-dev3/db/
mysql -uroot -p -e "source order.sql"
mysql -uroot -p -e "source product.sql"
mysql -uroot -p -e "source stock.sql"
```

## 四、在Kubernetes中部署jenkins

部署（略）
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/200511164028159.png)
jenkins pipeline就像一个管道的建模一样,在这个脚本里完成了整个生命周期各个阶段，从development开发提交代码commit id,到build构建，再到test测试，再到stage步骤做一些处理，deploy部署到dev或者qa环境中，最后到线上,其实在这个流程中它是有一个目的的，刚开始是在开发环境，最终是把它带到线上环境，而中间一系列的流程都是通过管道的形式串起来，而这个管道这个模型是通过pipeline去书写的，这个语法就是这个模型，需要把这个生命周期的所需的都套进这个模型中来，然后由jenkins pipeline去管理

pipepine它有很大的特点
1、可视化页面，每个步骤都可以可视化展示，方便我们去解决每个步骤的相关问题
2、每个步骤都写脚本里面了，只需要维护这个脚本就好了，而这个脚本可以写的具有通用性，如果想写多个项目时，比如发布3组微服务，那么第一个写的pipeline，那么也同样适用于第二个和第三个微服务的模版。那么这个需要考虑它们有哪些不同点？
不同点：

- 拉取git代码的地址不一样
- 分支名也不一样，因为是不同的git地址，所以打的分支名也不一样。
- 部署的机器也不一样，有可能这几个服务部署在node1,另外的服务部署在node2或者node3
- 打出的包名不一样

所以要把这些不同点，做成一种人工交互的形式去发布，这样的话这个脚本才具有通用性，发布服务才能使用这写好的pipeline发布更多的微服务，而且jenkins pipeline支持参数化构建。

五、jenkins在k8s中动态创建代理(略)

六、部署私有代码仓库gitlab(略)

七、基于kubernetes构建jenkins ci系统(略)

八、pipeline集成helm发布spring cloud微服务
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281523.png)
现在编写这个pipeline脚本来实现自动化发布微服务

```json
#!/usr/bin/env groovy
// 公共
def registry = "harbor.wzxmt.com"
// 项目
def git_url = "http://git.wzxmt.com:9999/root/simple-microservice.git"
def gateway_domain_name = "gateway.wzxmt.com"
def portal_domain_name = "portal.wzxmt.com"
def k8s_args="--kubeconfig /opt/admin.kubeconfig"
def k8s_ns_args="-n ${params.Namespace} --kubeconfig /opt/admin.kubeconfig"
// 认证
def image_pull_secret = "registry-pull-secret"
def harbor_registry_auth = "68c13df1-8979-42a2-9bfc-eecb8491212d"
def git_auth = "4cfda67a-5ae0-4c93-88cd-a91d9fc2ba8a"
// ConfigFileProvider ID
def k8s_auth = "bbafac8f-2d98-421f-af11-7ec9462e005b"

pipeline {
  agent {
    kubernetes {
      label "jenkins-slave"
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
    parameters {
        string defaultValue: 'app', description: 'harbor project', name: 'project', trim: true
        gitParameter branch: '', branchFilter: '.*', defaultValue: '', description: '选择发布的分支', name: 'Branch', quickFilterEnabled: false, selectedValue: 'NONE', sortMode: 'NONE', tagFilter: '*', type: 'PT_BRANCH'        
        extendedChoice defaultValue: 'none', description: '选择发布的微服务', \
          multiSelectDelimiter: ',', name: 'Service', type: 'PT_CHECKBOX', \
          value: 'gateway-service:9999,portal-service:8080,product-service:8010,order-service:8020,stock-service:8030'
        string defaultValue: '', description: '', name: 'add_tag', trim: true
        choice choices: ['maven-3.6.3', 'maven-3.6.0'], description: '', name: 'maven_version'
        choice choices: ['mvn clean package -Dmaven.test.skip=true', 'mvn clean install -Dmaven.test.skip=true -Dmaven.javadoc.skip=true'], description: '', name: 'mvn_cmd'
        choice (choices: ['ms', 'demo'], description: '部署模板', name: 'Template')
        choice (choices: ['1', '3', '5', '7'], description: '副本数', name: 'ReplicaCount')
        choice (choices: ['ms'], description: '命名空间', name: 'Namespace')
    }
    stages {
        stage('拉取代码'){
            steps {
                checkout([$class: 'GitSCM', 
                branches: [[name: "${params.Branch}"]], 
                doGenerateSubmoduleConfigurations: false, 
                extensions: [], submoduleCfg: [], 
                userRemoteConfigs: [[credentialsId: "${git_auth}", url: "${git_url}"]]
                ])
            }
        }
        stage('代码编译') {
            // 编译指定服务
            steps {
                sh """
                  /opt/${params.maven_version}/bin/${params.mvn_cmd}
                """
            }
        }
        stage('构建镜像') {
          steps {
              withCredentials([usernamePassword(credentialsId: "${harbor_registry_auth}", passwordVariable: 'password', usernameVariable: 'username')]) {
                sh """
                 echo "\${password}" | docker login --username admin --password-stdin ${registry}
                 for service in \$(echo ${Service} |sed 's/,/ /g'); do
                    service_name=\${service%:*}
                    image_name="${registry}/${params.project}/\${service_name}:${params.add_tag}"
                    cd \${service_name}
                    n=`ls |grep biz|wc -l`
                    if [ \$n -ne 0 ]; then
                        cd \${service_name}-biz
                    fi

                    docker build -t \${image_name} .
                    docker push \${image_name}
                    docker rmi \${image_name}
                    cd ${WORKSPACE}
                  done
                """
              configFileProvider([configFile(fileId: "${k8s_auth}", targetLocation: '/opt/admin.kubeconfig')]) {
                sh """
                    # 添加ns
                    m_ns=`kubectl get ns ${k8s_args} |grep -w ${Namespace}|wc -l`
                    if [ \${m_ns} -eq 0 ];then
                        kubectl create ns ${params.Namespace} ${k8s_args}
                    fi
                    # 添加镜像拉取认证
                    m_sc=`kubectl get secret ${k8s_ns_args}|grep -w ${image_pull_secret}|wc -l`
                    if [ \${m_sc} -eq 0 ];then
                        kubectl create secret docker-registry ${image_pull_secret} --docker-username=${username} \
                        --docker-password=${password} --docker-server=https://${registry} ${k8s_ns_args}
                    fi
                    # 添加私有chart仓库
                    # helm repo add  --username ${username} --password ${password} myrepo http://${registry}/chartrepo/${params.project} ${k8s_ns_args}
                   """
               }
             }
          }
        }
        stage('Helm部署到K8S') {
          steps {
              sh """
              for service in  \$(echo ${Service} |sed 's/,/ /g'); do
                service_name=\${service%:*}
                service_port=\${service#*:}
                image="${registry}/${params.project}/\${service_name}"
                tag=${params.add_tag}
                helm_args="\${service_name} --set image.repository=\${image} --set image.tag=\${tag} --set replicaCount=${replicaCount} \
                --set imagePullSecrets[0].name=${image_pull_secret} --set service.targetPort=\${service_port} library/${Template}"


                #判断是否为新部署
                if helm history \${service_name} ${k8s_args} &>/dev/null;then
                  action=upgrade
                else
                  action=install
                fi

                #针对服务启用ingress
                if [ \${service_name} == "gateway-service" ]; then
                  helm \${action} \${helm_args} \
                  --set ingress.enabled=true \
                  --set ingress.host=${gateway_domain_name} \
                   ${k8s_ns_args}
                elif [ \${service_name} == "portal-service" ]; then
                  helm \${action} \${helm_args} \
                  --set ingress.enabled=true \
                  --set ingress.host=${portal_domain_name} \
                   ${k8s_ns_args}
                else
                  helm \${action} \${helm_args} ${k8s_ns_args}
                fi
              done

              #查看Pod状态
              sleep 10
              kubectl get pods ${k8s_ns_args}
              """
          }
        }
    }
}
```

------

pipeline解析
1、首先去安装这几个插件

- Git Parameter 可以实现动态的从git中获取所有分支
- Git 拉取代码
- Pipeline 刚才安装的pipeline，来实现这个pipeline流水线的发布任务
- Config File Provider 主要可以将kubeconfig配置文件存放在jenkins里，让这个pipeline引用这个配置文件
- kubernetes 动态的去创建代理，好让k8s连接到jenkins，可以动态的去伸缩slave节点
- Extended Choice Parameter 进行对选择框插件进行扩展，可以多选，扩展参数构建，而且部署微服务还需要多选
- Blue Ocean 一个可视化、可编辑的流水线插件

2、参数含义
// 公共

```json
def registry = "https://harbor.wzxmt.com"   //镜像仓库
```

// 项目

```json
def project = "microservice" //项目的名称
def git_url = "https://github.com/wzxmt/simple-microservice.git" //微服务的gitlab的项目的git地址
def gateway_domain_name = "gateway.wzxmt.com" //微服务里面有几个对外提供服务，指定域名
def portal_domain_name = "portal.wzxmt.com" //微服务里面有几个对外提供服务，需指定域名
```

// 认证

```json
//部署应用的时候，拉取仓库的镜像与k8s进行认证imagePullSecrets，可以通过创建kubectl create secret docker-registry harborlogin --namespace=infra --docker-server=https://harbor.wzxmt.com --docker-username=admin --docker-password=admin
def image_pull_secret = "registry-pull-secret" 
//docker login密钥
def harbor_registry_auth = "e5402e52-7dd0-4daf-8d21-c4aa6e47736b" 
//gitlib认证密钥
def git_auth = "a65680b4-0bf7-418f-a77e-f20778f9e737" 
//k8s的认证信息
def k8s_auth = "7ee65e53-a559-4c52-8b88-c968a637051e" 
```

这些都是定义的公共的变量，这些变量主要是让脚本适用于一个通用性，将一些变动的值传入进去这样主要可以让项目动态的去适配了

3、动态的在k8s中去创建slave-pod

```yaml
pipeline {
  agent {
  kubernetes {
    label "jenkins-slave"
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
}
```

4、参数化构建

```json
    parameters {
        gitParameter branch: '', branchFilter: '.*', defaultValue: '', description: '选择发布的分支', name: 'Branch', quickFilterEnabled: false, selectedValue: 'NONE', sortMode: 'NONE', tagFilter: '*', type: 'PT_BRANCH'        
        extendedChoice defaultValue: 'none', description: '选择发布的微服务', \
          multiSelectDelimiter: ',', name: 'Service', type: 'PT_CHECKBOX', \
          value: 'gateway-service:9999,portal-service:8080,product-service:8010,order-service:8020,stock-service:8030'
        choice (choices: ['ms', 'demo'], description: '部署模板', name: 'Template')
        choice (choices: ['1', '3', '5', '7'], description: '副本数', name: 'ReplicaCount')
        choice (choices: ['ms'], description: '命名空间', name: 'Namespace')
    }
```

微服务找出我们需要哪些需要人工交互的,就是使用的这套微服务都适用于这套chart模版

- 微服务名称，以及针对一些服务需要带上域名，另外比如去配置的微服务的名字都是不一样的，这个名字是保证是唯一的，需要使用include，，一般写在_helpers。tpl下，因为我们部署的时候已经拿到微服务的名称了，所以helm起的名字也是微服务的名字，然后再加上公用的标签就区分出来了，另外就是微服务的端口也是不一样的
- 端口，每个微服务的端口也都不一
- 命名空间 使用helm -n 就可以部署到指定的命名空间了
- 副本数 这个本来在helm中是3个副本，我们可以通过传参的形式变成5或者2都可以
- 资源的限制，本身这个k8s中的限制是无法满足一个java应用的限制的，一般1.8jdk版本是不兼容的，新的版本是兼容的，所以手动的去指定它的对内存的
- 大小，这个一般在dockerfile启用jar包的时候带入
- chart模版的选择 可能一个项目满足不了一个项目，那么可能就得需要两个模版来实现

然后需要将这个chart模版添加到repo里,将helm制作完成后打包并push到仓库中，然后当我们部署的时候就去拉这个helm模版地址

```bash
helm push ms-0.1.0.tgz --ca-file=ca.crt --cert-file=harbor.wzxmt.com.crt --key-file=harbor.wzxmt.com.key --username=admin --password=admin library
```

5、jenkins-slave所执行的具体任务

```json
  stages {
        stage('拉取代码'){
            steps {
                checkout([$class: 'GitSCM',                      
                branches: [[name: "${params.Branch}"]], 
                doGenerateSubmoduleConfigurations: false, 
                extensions: [], submoduleCfg: [], 
                userRemoteConfigs: [[credentialsId: "${git_auth}", url: "${git_url}"]]     //它需要将这个参数传给上面的git parameters,让它能够动态的git地址中拉取所有的分支，
                ])
            }
        }
        stage('代码编译') {
            // 编译指定服务
            steps {
                sh """
                  mvn clean package -Dmaven.test.skip=true           
                """
            }
        }
        stage('构建镜像') {
          steps {
              withCredentials([usernamePassword(credentialsId: "${harbor_registry_auth}", passwordVariable: 'password', usernameVariable: 'username')]) {    //这里使用了一个凭据的认证将连接harbor认证信息保存到凭据里面，为了安全性，使用了凭据的引用，动态的将它保存到变量中，然后通过调用变量的形式去登录这镜像仓库，这样的话就不用在pipeline中去体现密码了，
                sh """
                 docker login -u ${username} -p '${password}' ${registry}
                 for service in \$(echo ${Service} |sed 's/,/ /g'); do
                    service_name=\${service%:*}   //因为我们是部署的微服务，所以我们需要很多的服务的构建，所以这里加了一个for循环,它调用的$service正是参数化构建中的选择的services,然后根据不同的服务推送到镜像仓库，
                    image_name=${registry}/${project}/\${service_name}:${BUILD_NUMBER}
                    cd \${service_name}
                    if ls |grep biz &>/dev/null; then
                        cd \${service_name}-biz
                    fi
                    docker build -t \${image_name} .
                    docker push \${image_name}
                    cd ${WORKSPACE}
                  done
                """   
                     //之前说需要kubeconfig这个配置存到jenins中的slave的pod中，起个名字叫admin.kubeconfig
                configFileProvider([configFile(fileId: "${k8s_auth}", targetLocation: "admin.kubeconfig")]){
                    sh """
                    //添加镜像拉取认证   当使用拉取镜像的认证信息的时候就可以直接指定admin.kubeconfig了，它就能连接到这个集群了
                    kubectl create secret docker-registry ${image_pull_secret} --docker-username=${username} --docker-password=${password} --docker-server=${registry} -n ${Namespace} --kubeconfig admin.kubeconfig |true
                    //添加私有chart仓库到这个pod中
                    helm repo add  --username ${username} --password ${password} myrepo http://${registry}/chartrepo/${project}
                    """
                }
              }
          }
        }
```

6、deploy，使用helm部署到k8s中

```json
stage('Helm部署到K8S') {
          steps {
              sh """
              //定义公共的参数，使用helm,kubectl都要加namespace命名空间，连接k8s认证的kubeconfig文件
              common_args="-n ${Namespace} --kubeconfig admin.kubeconfig"

              for service in  \$(echo ${Service} |sed 's/,/ /g'); do       
              //for循环每个微服务的端口都不一样，所以在微服务这里添加微服务的名字和它对应的端口，把选择的服务和端口进行拆分
                service_name=\${service%:*}
                service_port=\${service#*:}
                image=${registry}/${project}/\${service_name}

                tag=${BUILD_NUMBER} //jenkins构建的一个编号
                helm_args="\${service_name} --set image.repository=\${image} --set image.tag=\${tag} --set replicaCount=${replicaCount} --set imagePullSecrets[0].name=${image_pull_secret} --set service.targetPort=\${service_port} myrepo/${Template}"

                //判断是否为新部署，那么加一个判断看看是不是部署了，为假就install，为真就upgrade
                if helm history \${service_name} \${common_args} &>/dev/null;then 
                  action=upgrade //旧部署的使用upgrade更新
                else
                  action=install //新部署的使用install
                fi

                //针对服务启用ingress
                if [ \${service_name} == "gateway-service" ]; then
                  helm \${action} \${helm_args} \
                //为true就启用ingress，因为chart肯定默认的为force，就是不启用ingress
                  --set ingress.enabled=true \  
                  --set ingress.host=${gateway_domain_name} \
                   \${common_args}
                elif [ \${service_name} == "portal-service" ]; then 
                  helm \${action} \${helm_args} \
                  --set ingress.enabled=true \
                  --set ingress.host=${portal_domain_name} \
                   \${common_args}
                else
                  helm \${action} \${helm_args} \${common_args} 
                fi
              done
              //查看Pod状态
              sleep 10
              kubectl get pods \${common_args}
              """
          }
        }
    }
```

修改凭据

![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/200511164028156.png)
点击jenkins
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281526.png)
add 添加凭据
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281534.png)
填写harbor的用户名和密码，密码Harbor12345
描述随便写,
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281535.png)
再添加第二个
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281540.png)
git的用户名和密码
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281524.png)
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281543.png)
将这个id放到pipeline中
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281545.png)
将生成的密钥认证放到pipeline中

现在去添加kubeconfig的文件
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281518.png)
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281541.png)
将这个ID放到我们k8s-auth的pipeline中，这个配置文件是k8s连接kubeconfig的ID，cat /root/.kube/config 这个文件下将文件拷贝到jenkins中
![通过jenkins交付微服务到kubernetes](https://www.linuxidc.com/upload/2020_05/2005111640281529.png)

最后进行测试发布在pipeline的配置指定发布的服务进行发布
查看pod的状态


