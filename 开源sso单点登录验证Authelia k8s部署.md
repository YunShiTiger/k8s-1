**一. 部署Authelia至k8s**

注意部署时最好不要配置到kube-system这个ns,因为默认情况下是没有权限去访问kube-system

```bash
mkdir -p sso-authelia/config  && cd sso-authelia
```

创建名称空间

```bash
kubectl create ns sso
```

[创建配置文件](https://github.com/authelia/authelia/blob/master/config.template.yml)

```yaml
cat<< EOF >config/configuration.yml
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
  ldap:
    implementation: custom
    url: ldap://127.0.0.1
    start_tls: false
    tls:
      skip_verify: false
      minimum_version: TLS1.2
    base_dn: dc=example,dc=com
    additional_users_dn: ou=users
    users_filter: (&({username_attribute}={input})(objectClass=person))
    additional_groups_dn: ou=groups
    groups_filter: (&(member={dn})(objectclass=groupOfNames))
    user: cn=admin,dc=example,dc=com
    password: password

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
```

创建configmap

```bash
kubectl -n sso create configmap oss-config --from-file=config
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
          configMap:
            name: oss-config
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
    - web
  routes:
  - match: Host(`authelia.wzxmt.com`) && PathPrefix(`/`)
    kind: Rule
    services:
    - name: sso-authelia
      port: 9091
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
    address: http://sso-authelia.sso:9091/api/verify?rd=http://authelia.wzxmt.com/
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