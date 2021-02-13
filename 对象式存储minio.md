### 对象式存储minio

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

