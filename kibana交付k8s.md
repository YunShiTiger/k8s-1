拉取镜像

```bash
docker pull kibana:7.7.1
docker tag kibana:7.7.1 harbor.wzxmt.com/infra/kibana:7.7.1
docker push harbor.wzxmt.com/infra/kibana:7.7.1
```

资源清单

```bash
mkdir /data/software/yaml/kibana -p
cd /data/software/yaml/kibana
```

ConfigMap

```yaml
cat << 'EOF' >cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kibana-conf
  namesppace: es
data:
  kibana.yml: |
    server.name: kibana
    server.host: "0"
    i18n.locale: "zh-CN"
    elasticsearch.hosts: [ "http://elasticsearch:9200" ]
    elasticsearch.requestTimeout: 600000
    monitoring.ui.container.elasticsearch.enabled: true
EOF
```

Deployment

```yaml
cat << 'EOF' >dp.yaml
kind: Deployment
apiVersion: apps/v1
metadata:
  name: kibana
  namespace: es
spec:
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      es-app: kibana
  template:
    metadata:
      labels:
        es-app: kibana
    spec:
      imagePullSecrets:
      - name: harborlogin
      containers:
        - name: kibana
          image: harbor.wzxmt.com/infra/kibana:7.7.1
          ports:
            - containerPort: 5601
              protocol: TCP
          volumeMounts:
            - mountPath: /usr/share/kibana/config
              name: kibana-conf-volume
      volumes:
        - name: kibana-conf-volume
          configMap:
            name: kibana-conf
EOF
```

Service

```yaml
cat << 'EOF' >svc.yaml
kind: Service
apiVersion: v1
metadata:
  name: kibana
  namespace: es
spec:
  selector:
   es-app: kibana
  ports:
    - port: 5601
      targetPort: 5601
EOF
```

Ingress

```yaml
cat << 'EOF' >ingress.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: kibana
  namespace: es
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
    - host: kibana.wzxmt.com
      http:
        paths:
        - path: /
          backend:
            serviceName: kibana
            servicePort: 5601
EOF
```

部署

```bash
kubectl apply -f ./
```

dns添加域名解析

```bash
kibana	60 IN A 10.0.0.50
```

访问[http://kibana.wzxmt.com](http://kibana.wzxmt.com)

