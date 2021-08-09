## 一、MinIO 简介

MinIO 是一个基于Apache License v2.0开源协议的对象存储服务。它兼容亚马逊S3云存储服务接口，非常适合于存储大容量非结构化的数据，例如图片、视频、日志文件、备份数据和容器/虚拟机镜像等，而一个对象文件可以是任意大小，从几kb到最大5T不等。

MinIO是一个非常轻量的服务,可以很简单的和其他应用的结合，类似 NodeJS, Redis 或者 MySQL。

## 二、MinIO 优点

- 高性能 minio是世界上最快的对象存储(官网说的: min.io/)
- 弹性扩容 很方便对集群进行弹性扩容
- 天生的云原生服务
- 开源免费,最适合企业化定制
- S3事实标准
- 简单强大，安装部署简单
- 丰富的SDK支持
- 存储机制(Minio使用纠删码erasure code和校验和checksum来保护数据免受硬件故障和无声数据损坏。 即便丢失一半数量（N/2）的硬盘，仍然可以恢复数据)

## 三、kebernetes分布式部署MinIO

#### 私有镜像

```bash
docker pull minio/minio:RELEASE.2021-02-14T04-01-33Z
docker tag minio/minio:RELEASE.2021-02-14T04-01-33Z harbor.wzxmt.com/infra/minio:latest
docker push harbor.wzxmt.com/infra/minio:latest
```

#### 创建名称空间

```bash
kubectl create ns minio
```

#### 创建docker-registry认证

```bash
kubectl create secret docker-registry harborlogin \
--namespace=minio \
--docker-server=https://harbor.wzxmt.com \
--docker-username=admin \
--docker-password=admin
```

####  base64 编码格式

```
echo -n "admin" | base64
```

#### 资源清单

```yaml
cat<< 'EOF' >minio.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: minio-data
provisioner: fuseim.pri/ifs
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: "minio"
  namespace: "minio"
  labels:
    app: minio
    version: minio-8.0.10
    release: "minio"
---
apiVersion: v1
kind: Secret
metadata:
  name: minio
  namespace: "minio"
  labels:
    app: minio
    version: minio-8.0.10
    release: minio
type: Opaque
data:
  accesskey: "YWRtaW4="
  secretkey: "YWRtaW4xMjM="
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: "minio"
  labels:
    app: minio
    version: minio-8.0.10
    release: minio
spec:
  updateStrategy:
    type: RollingUpdate
  podManagementPolicy: "Parallel"
  serviceName: minio-svc
  replicas: 4
  selector:
    matchLabels:
      app: minio
      release: minio
  template:
    metadata:
      name: minio
      labels:
        app: minio
        release: minio
    spec:
      serviceAccountName: "minio"
      imagePullSecrets:
      - name: harborlogin
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: minio
          image: harbor.wzxmt.com/infra/minio:latest
          imagePullPolicy: IfNotPresent
          command: [ "/bin/sh",
            "-ce",
            "/usr/bin/docker-entrypoint.sh minio -S /etc/minio/certs/ server  http://minio-{0...3}.minio-svc.minio.svc.cluster.local/export" ]
          volumeMounts:
            - name: export
              mountPath: /export
          ports:
            - name: http
              containerPort: 9000
          env:
            - name: MINIO_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: minio
                  key: accesskey
            - name: MINIO_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: minio
                  key: secretkey
      volumes:
        - name: minio-user
          secret:
            secretName: minio
  volumeClaimTemplates:
    - metadata:
        name: export
      spec:
        accessModes: [ "ReadWriteOnce" ]
        storageClassName: minio-data
        resources:
          requests:
            storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: "minio"
  labels:
    app: minio
    version: minio-8.0.10
    release: minio
spec:
  type: NodePort
  ports:
    - name: http
      port: 9000
      protocol: TCP
      nodePort: 32000
  selector:
    app: minio
    release: minio
---
apiVersion: v1
kind: Service
metadata:
  name: minio-svc
  namespace: "minio"
  labels:
    app: minio
    version: minio-8.0.10
    release: "minio"
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  ports:
    - name: http
      port: 9000
      protocol: TCP
  selector:
    app: minio
    release: minio
---
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
      port: 9000
EOF
```

部署

```bash
kubectl apply -f minio.yaml
```

## 四、helm部署

#### 生成StorageClass

```yaml
cat<< 'EOF' >sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: minio-data
provisioner: fuseim.pri/ifs
EOF
kubectl apply -f sc.yaml
```

#### helm部署

```bash
helm install minio \
  --namespace minio --create-namespace \
  --set accessKey=minio,secretKey=minio123 \
  --set mode=distributed \
  --set replicas=4 \
  --set service.type=NodePort \
  --set service.nodePort=32000 \
  --set persistence.size=10Gi \
  --set persistence.storageClass=minio-data \
  --set accessKey=admin \
  --set secretKey=admin123 \
  minio/minio
```

ingressroute

```yaml
cat<< 'EOF' >ingressroute.yaml
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
      port: 9000
EOF
kubectl apply -f ingressroute.yaml
```

