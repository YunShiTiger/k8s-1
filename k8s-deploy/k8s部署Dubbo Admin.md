## 构建Dubbo-Admin工程

准备java环境（略）

克隆Dubbo Admin仓库：

```bash
git clone -b master --depth=1 https://github.com/apache/dubbo-admin.git
```

其中：

-b master: 指定要克隆的是master分支。Dubbo Admin仓库的默认分支是develop，所以要切换
--depth=1: 只克隆最新一次提交记录。避免下载仓库历史，增加下载时间。
进入工程目录：

```bash
cd dubbo-admin/dubbo-admin
```

开始构建：

```bash
mvn clean package -Dmaven.test.skip=true
```

最终生成的jar包：

target/dubbo-admin-0.0.1-SNAPSHOT.jar

## 构建Dubbo-Admin Docker镜像

编写Dockerfile：

```bash
cat << EOF >Dockerfile
FROM openjdk:8-jdk-alpine
RUN mkdir -p /dubbo-admin/config
ADD app.jar entrypoint.sh /dubbo-admin/
EXPOSE 7001
ENTRYPOINT  ["sh","/dubbo-admin/entrypoint.sh"]
EOF
```

构建准备

```bash
cat << EOF >entrypoint.sh
java -Djava.security.egd=file:/dev/urandom -Dspring.config.location=/dubbo-admin/config/application.properties -jar /dubbo-admin/app.jar
EOF
chmod +x entrypoint.sh
mv ./target/dubbo-admin-0.0.1-SNAPSHOT.jar app.jar
```

构建镜像并推送至镜像仓库：

```bash
docker build -t harbor.wzxmt.com/infra/dubbo-admin:latest .
docker push harbor.wzxmt.com/infra/dubbo-admin:latest
```

## 部署Dubbo-Admin

```bash
mkdir -p dubbo-admin && cd dubbo-admin
```

cm

```yaml
cat << 'EOF' >cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:  
  name: dubbo-admin-config
  namespace: infra
data:  
  application.properties: |
    server.port=7001
    spring.velocity.cache=false
    spring.velocity.charset=UTF-8
    spring.velocity.layout-url=/templates/default.vm
    spring.messages.fallback-to-system-locale=false
    spring.messages.basename=i18n/message
    spring.root.password=root
    spring.guest.password=guest
    dubbo.registry.address=zookeeper://zk-0.zk-hs:2181?backup=zk-1.zk-hs:2181,zk-2.zk-hs:2181
EOF
```

Deployment

```yaml
cat << 'EOF' >dp.yaml
kind: Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    name: dubbo-admin
  name: dubbo-admin
  namespace: infra
spec:
  replicas: 3
  selector:
    matchLabels:
      name: dubbo-admin
  template:
    metadata:
      labels:
        name: dubbo-admin
    spec:
      containers:
      - name: dubbo-admin
        image: harbor.wzxmt.com/infra/dubbo-admin:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 7001
          protocol: TCP
        volumeMounts:
        - mountPath: /dubbo-admin/config
          name: dubbo-admin-config
      imagePullSecrets:
      - name: harborlogin
      volumes:
      - name: dubbo-admin-config
        configMap: 
          name: dubbo-admin-config    
EOF
```

Service

```yaml
cat << 'EOF' >svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: dubbo-admin
  namespace: infra
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 7001
  selector:
    name: dubbo-admin
EOF
```

Ingress

```yaml
cat << 'EOF' >ingress.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: dubbo-admin
  namespace: infra
spec:
  entryPoints:
    - web
  routes:
  - match: Host(`dubbo-admin.wzxmt.com`) && PathPrefix(`/`)
    kind: Rule
    services:
    - name: dubbo-admin
      port: 80
EOF
```

DNS解析域名：

~~~
dubbo-admin              A    10.0.0.50
~~~

部署:

~~~
kubectl apply -f ./
~~~

http://dubbo-admin.wzxmt.com

