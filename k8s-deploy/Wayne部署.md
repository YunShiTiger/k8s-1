创建名称空间

```bash
kubectl create ns wayne
```

mysql

```yaml
cat << EOF >
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql-wayne
  namespace: wayne
  labels:
    app: mysql-wayne
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql-wayne
  template:
    metadata:
      labels:
        app: mysql-wayne
    spec:
      containers:
      - name: mysql
        image: 'mysql:5.6.41'
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: root
        resources:
          limits:
            cpu: '1'
            memory: 2Gi
          requests:
            cpu: '1'
            memory: 2Gi
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: mysql-wayne
  name: mysql-wayne
  namespace: wayne
spec:
  ports:
  - port: 3306
    protocol: TCP
    targetPort: 3306
  selector:
    app: mysql-wayne
EOF
```

backend

```yaml
cat<< 'EOF' >wayne-backend.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    app: wayne-backend
  name: wayne-backend
  namespace: wayne
data:
  app.conf: |-
    appname = wayne
    httpport = 8080
    runmode = prod
    autorender = false
    copyrequestbody = true
    EnableDocs = true
    EnableAdmin = true
    StaticDir = public:static

    # Custom config
    ShowSql = false

    ## if enable username and password login
    EnableDBLogin = true

    # token, generate jwt token
    RsaPrivateKey = "./apikey/rsa-private.pem"
    RsaPublicKey = "./apikey/rsa-public.pem"

    # token end time. second
    TokenLifeTime=86400

    # kubernetes labels config
    AppLabelKey= wayne-app
    NamespaceLabelKey = wayne-ns
    PodAnnotationControllerKindLabelKey = wayne.cloud/controller-kind

    # database configuration:
    ## mysql
    DBName = "wayne"
    DBTns = "tcp(mysql-wayne:3306)"
    DBUser = "root"
    DBPasswd = "root"
    DBConnTTL = 30

    # web shell auth
    appKey = "860af247a91a19b2368d6425797921c6"

    # Set demo namespace and group id
    DemoGroupId = "1"
    DemoNamespaceId = "1"

    # Sentry
    LogLevel = "4"
    SentryEnable = false
    SentryDSN = ""
    SentryLogLevel = "4"

    # Robin
    EnableRobin = false

    # api-keys
    EnableApiKeys = true

    # Bus
    BusEnable = false

    # Webhook
    EnableWebhook = true
    WebhookClientTimeout = 10
    WebhookClientWindowSize = 16
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: wayne-backend
  name: wayne-backend
  namespace: wayne
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wayne-backend
  template:
    metadata:
      labels:
        app: wayne-backend
    spec:
      volumes:
      - name: config
        configMap:
          name: wayne-backend
      containers:
      - name: wayne
        image: '360cloud/wayne-backend:v1.8.6'
        command:
        - /opt/wayne/backend
        - apiserver
        env:
        - name: GOPATH  # app.conf runmode = dev must set GOPATH
          value: /go
        resources:
          limits:
            cpu: '0.5'
            memory: 1Gi
          requests:
            cpu: '0.5'
            memory: 1Gi
        volumeMounts:
        - name: config
          mountPath: /opt/wayne/conf/
        readinessProbe:
          httpGet:
            path: healthz
            port: 8080
          timeoutSeconds: 1
          periodSeconds: 10
          failureThreshold: 3
        imagePullPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: wayne-backend
  name: wayne-backend
  namespace: wayne
spec:
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app: wayne-backend
EOF
```

frontend

```yaml
cat<< 'EOF' >wayne-frontend.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    app: wayne-frontend
  name: wayne-frontend
  namespace: wayne
data:
  config.js: |-
    window.CONFIG = {
      URL: 'http://wayne-backend.wzxmt.com',
      RAVEN: false,
      RAVEN_DSN: 'RAVEN_DSN'
    };
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: wayne-frontend
  name: wayne-frontend
  namespace: wayne
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wayne-frontend
  template:
    metadata:
      labels:
        app: wayne-frontend
    spec:
      volumes:
      - name: config
        configMap:
          name: wayne-frontend
          items:
          - key: config.js
            path: config.js
      containers:
      - name: wayne
        image: '360cloud/wayne-frontend:latest'
        resources:
          limits:
            cpu: '0.5'
            memory: 1Gi
          requests:
            cpu: '0.5'
            memory: 1Gi
        volumeMounts:
        - name: config
          mountPath: /usr/local/openresty/nginx/html/config.js
          subPath: config.js
        imagePullPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: wayne-frontend
  name: wayne-frontend
  namespace: wayne
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: wayne-frontend
EOF
```

ingress

```yaml
cat<< 'EOF' >wayne-ingress.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: wayne-frontend
  namespace: wayne
spec:
  entryPoints:
    - web
  routes:
  - match: Host(`wayne.wzxmt.com`) && PathPrefix(`/`)
    kind: Rule
    services:
    - name: wayne-frontend
      port: 80
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: wayne-backend
  namespace: wayne
spec:
  entryPoints:
    - web
  routes:
  - match: Host(`wayne-backend.wzxmt.com`) && PathPrefix(`/`)
    kind: Rule
    services:
    - name: wayne-backend
      port: 8080
EOF
```

