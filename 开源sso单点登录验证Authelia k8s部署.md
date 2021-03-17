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

```yaml
cat<< EOF >/data/nfs-volume/sso/configuration.yml
host: 0.0.0.0
port: 9091
log_level: debug
jwt_secret: a_very_important_secret
default_redirection_url: https://public.wzxmt.com  #默认重定向url
totp:
  issuer: authelia.com

authentication_backend:
  disable_reset_password: false
  refresh_interval: 5m
  file:
    path: /config/users_database.yml
access_control:
  default_policy: deny
  rules:
    - domain: public.wzxmt.com
      policy: bypass   #其实是bypassed绕过验证，一般生产这个不会用
    - domain: traefik.wzxmt.com
      policy: one_factor #需要一个验证条件
    - domain: secure.wzxmt.com
      policy: two_factor #需要两个验证条件

session:
  name: authelia_session
  secret: unsecure_session_secret
  expiration: 3600 # 1 hour
  inactivity: 300 # 5 minutes
  domain: wzxmt.com # 被保护的域名

regulation:
  max_retries: 3
  find_time: 120
  ban_time: 300

storage:
  mysql:
    host: mysql.wzxmt.com
    port: 3306
    database: authelia
    username: authelia
    password: authelia

notifier:
  disable_startup_check: false
  smtp:
    username: 1451343603@qq.com
    password: lqukswqzhnvqjcbj
    sender: 1451343603@qq.com
    host: smtp.qq.com
    port: 465
EOF
cat<< EOF >/data/nfs-volume/sso/users_database.yml
# List of users
users:
  wrx:
    displayname: "wrx"
    password: "$6$rounds=50000$BpLnfgDsc2WD8F2q$Zis.ixdg9s/UOJYrs56b5QEZFiZECu0qZVNsIYxBaNJ7ucIL.nlxVCT5tqh8KHG8X4tlwCFm5r6NTOZZ5qRFN/"
    email: wrx@xxx.com
    groups:
      - admins
      - dev
EOF
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
      - image: authelia/authelia
        name: sso-authelia
        volumeMounts:
        - name: oauthelia-configmap
          mountPath: /config/
        ports:
        - containerPort: 9091
          protocol: TCP
      imagePullSecrets:
        - name: IfNotPresent
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