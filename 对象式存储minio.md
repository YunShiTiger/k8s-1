Minio 是一个基于Go语言的对象存储服务。它实现了大部分亚马逊S3云存储服务接口，可以看做是是S3的开源版本，非常适合于存储大容量非结构化的数据，例如图片、视频、日志文件、备份数据和容器/虚拟机镜像等，而一个对象文件可以是任意大小，从几kb到最大5T不等。区别于分布式存储系统，MinIO的特色在于简单、轻量级，对开发者友好，认为存储应该是一个开发问题而不是一个运维问题。

MinIO支持Kubernetes原生云环境部署和使用。

![img](https://www.mayi888.com/wp-content/uploads/2020/02/Snip20200220_5.png)

它可以作为大数据数据存取平台。官网数据公布MinIO运行Apache Spark大数据分析平台效率高于HDFS和亚马逊S3文件系统。

![img](https://www.mayi888.com/wp-content/uploads/2020/02/Snip20200220_6.png)

它与Amazon S3云存储服务兼容。它最适合存储非结构化数据，如照片，视频，日志文件，备份和容器/ VM映像。对象的大小可以从几KB到最大5TB。可以实现MinIO私有云和S3协议兼容公有云之间数据的同步。

![img](https://www.mayi888.com/wp-content/uploads/2020/02/Snip20200220_8.png)

MinIO开源（Apache License v2.0）分布式存储系统可以作为原生云数据存储基础设施，应用程序、机器学习、数据处理和流数据都可以存储在该系统中。

![img](https://www.mayi888.com/wp-content/uploads/2020/02/Snip20200220_9.png)

- [服务端](https://docs.min.io/)，可通过web访问
- [客户端](https://docs.min.io/docs/minio-client-quickstart-guide.html)

### 对象存储方法

bucket管理

```
cp 远程本地相互拷贝，或远程与远程，本地与本地操作
mirror 设置远程bucket与本地目录一致
```

对象获取方法

```
share 创建http下载链接，有效期最长7天
mirror 可设置watch，保持远程与本地同步更新
watch event，间接操作，接收event通知，自定义操作
```

#### 创建镜像仓库与准备镜像

```bash
docker pull minio/minio:latest
docker tag minio/minio:latest harbor.wzxmt.com/infra/minio:latest
docker push harbor.wzxmt.com/infra/minio:latest
```

#### 创建名称空间

```bash
kubectl create ns minio
```

#### 创建docker-registry认证

```bash
kubectl create secret docker-registry harbor \
--namespace=minio  \
--docker-server=https://harbor.wzxmt.com \
--docker-username=admin \
--docker-password=admin
```

#### 资源清单

```bash
mkdir -p minio && cd minio
```

Deployment

```yaml
cat << 'EOF' >dp.yaml
kind: Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    name: minio
  name: minio
  namespace: minio
spec:
  progressDeadlineSeconds: 600
  replicas: 3
  revisionHistoryLimit: 7
  selector:
    matchLabels:
      name: minio
  template:
    metadata:
      labels:
        app: minio
        name: minio
    spec:
      containers:
      - name: minio
        image: harbor.wzxmt.com/infra/minio:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 9000
          protocol: TCP
        args:
        - server
        - /data
        env:
        - name: MINIO_ACCESS_KEY
          value: admin
        - name: MINIO_SECRET_KEY
          value: admin123
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /minio/health/ready
            port: 9000
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 5
        volumeMounts:
        - mountPath: /data
          name: data
      imagePullSecrets:
      - name: harbor
      volumes:
      - nfs:
          server: nfs.wzxmt.com
          path: /data/nfs-volume/minio
        name: data
EOF
```

Service

```yaml
cat << 'EOF' >svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 9000
  selector:
    app: minio
EOF
```

Ingress

```yaml
cat << 'EOF' >ingress.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: minio
  namespace: minio
spec:
  entryPoints:
    - web
  routes:
  - match: Host(`minio.wzxmt.com`) && PathPrefix(`/`)
    kind: Rule
    services:
    - name: minio
      port: 80
EOF
```

#### 创建对应的存储

~~~bash
mkdir -p /data/nfs-volume/minio
~~~

#### DNS解析域名：

~~~
minio              A    10.0.0.50
~~~

> 为什么每次每次都不用些 wzxmt.com，是因为第一行有$ORIGIN  wzxmt.com. 的宏指令，会自动补

#### 应用清单:

~~~
kubectl apply -f ./
~~~

http://minio.wzxmt.com

账户：admin

密码：admin123

![158399429267](C:/Users/wzxmt/Desktop/k8s/acess/1583994292679.png)

