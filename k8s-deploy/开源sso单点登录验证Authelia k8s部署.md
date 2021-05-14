**一. 部署Authelia至k8s**

注意部署时最好不要配置到kube-system这个ns,因为默认情况下是没有权限去访问kube-system

```bash
mkdir -p sso-authelia  && cd sso-authelia
```

创建名称空间

```bash
kubectl create ns sso
```

创建sso-config存储目录

```bash
mkdir -p /data/nfs-volume/sso
```

镜像私有化

```bash
docker pull authelia/authelia
docker tag authelia/authelia harbor.wzxmt.com/infra/authelia:latest
docker push harbor.wzxmt.com/infra/authelia:latest
```

创建docker-registry

```bash
kubectl create namespace infra
kubectl create secret docker-registry harborlogin \
--namespace=sso  \
--docker-server=https://harbor.wzxmt.com \
--docker-username=admin \
--docker-password=admin
```

创建pv

```yaml
cat << EOF >pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: authelia-pv
spec:
  storageClassName: nfs
  nfs:
    path: /data/nfs-volume/sso
    server: nfs.wzxmt.com
  persistentVolumeReclaimPolicy: Recycle
  accessModes:
  - ReadWriteMany
  capacity:
    storage: 1Gi
EOF
cat << EOF >pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: authelia-pv-claim
  namespace: sso
spec:
  storageClassName: nfs
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
EOF
kubectl apply -f pv.yaml -f pvc.yaml
```

[创建配置文件](https://github.com/authelia/authelia/blob/master/config.template.yml)

使用docker创建的配置文件

```bash
cp authelia/examples/compose/local/authelia/* /data/nfs-volume/sso
```

部署清单

```yaml
cat << EOF >dp.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: sso-authelia
  name: sso-authelia
  namespace: sso
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sso-authelia
  template:
    metadata:
      labels:
        app: sso-authelia
    spec:
      containers:
      - image: harbor.wzxmt.com/infra/authelia:latest
        name: sso-authelia
        volumeMounts:
        - name: oauthelia-configmap
          mountPath: /config/
        ports:
        - containerPort: 9091
          protocol: TCP
      imagePullSecrets:
      - name: harborlogin
      volumes:
        - name: oauthelia-configmap
          persistentVolumeClaim:
            claimName: authelia-pv-claim
EOF
```

svc

```yaml
cat << EOF >sc.yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: sso-authelia
  name: sso-authelia
  namespace: sso
spec:
  ports:
  - name: http
    port: 9091
    protocol: TCP
    targetPort: 9091
  selector:
    app: sso-authelia
EOF
```

ingress

```yaml
cat << 'EOF' >ingress.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: sso-authelia
  namespace: sso
spec:
  entryPoints:
    - websecure
  routes:
  - match: Host(`login.wzxmt.com`) && PathPrefix(`/`)
    kind: Rule
    services:
    - name: sso-authelia
      port: 9091
  tls:
    certResolver: myresolver
EOF
```

**二. 在traefik当中定义Middleware**

```yaml
cat << 'EOF' >middleware.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: sso-authelia
spec:
  forwardAuth:
    address: http://sso-authelia.sso:9091/api/verify?rd=https://login.wzxmt.com/
    trustForwardHeader: true
    authResponseHeaders:
      - "Remote-User"
      - "Remote-Groups"
      - "Remote-Name"
      - "Remote-Email"
EOF
```

**三. 在traefik当中调用Middleware**

```yaml
cat << 'EOF' >ingressRoute-middleware.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: simpleingressroute
spec:
  entryPoints:
    - websecure
  routes:
  - match: HostRegexp(`who.wzxmt.com`)
    kind: Rule
    services:
    - name: whoami
      port: 80
    middlewares:
    - name: sso-authelia
  tls:
    certResolver: myresolver
EOF
```

测试跳转验证：

访问：https://who.wzxmt.com 访问后自动跳转至验证页面，注意: session和cookie只能通过 https传输

注意：

```
user：wzxmt
password：wzxmt
```

