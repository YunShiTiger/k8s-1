下载镜像并推送harbor仓库

```bash
docker pull logstash:7.7.1
dockers tag logstash:7.7.1 harbor.wzxmt.com/infra/logstash:7.7.1
```

编写资源清单

 ConfigMap

```yaml
cat << 'EOF' >cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: logstash-pipeline-volume
  namespace: es
data:
  pipelines.yml: |
     - pipeline.id: main
       path.config: "/usr/share/logstash/pipeline"
EOF
```

Deployment

```yaml
cat << 'EOF' >dp.yaml
kind: Deployment
apiVersion: apps/v1
metadata:
  labels:
   es-app: logstash
  name: logstash
  namespace: es
spec:
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
     es-app: logstash
  template:
    metadata:
      labels:
       es-app: logstash
    spec:
      imagePullSecrets:
      - name: harborlogin
      containers:
        - name: logstash
          image: harbor.wzxmt.com/infra/logstash:7.7.1
          volumeMounts:
            - mountPath: /usr/share/logstash/pipeline
              name: logstash-conf-volume
            - mountPath: /usr/share/logstash/config/pipelines.yml
              name: pipeline-conf-volume
              subPath: pipelines.yml
          ports:
            - containerPort: 8080
              protocol: TCP
          env:
            - name: "XPACK_MONITORING_ELASTICSEARCH_URL"
              value: "http://elasticsearch-discovery:9200"
            - name: "XPACK_MONITORING_ENABLED"
              value: "true"
          securityContext:
            privileged: true
      volumes:
        - name: logstash-conf-volume
          persistentVolumeClaim:
            claimName: logstash-conf-pvc
        - name: pipeline-conf-volume
          configMap:
            name: logstash-pipeline-volume
EOF
```

Service

```yaml
cat << 'EOF' >svc.yaml
kind: Service
apiVersion: v1
metadata:
  labels:
    es-app: logstash
  name: logstash-service
  namespace: es
spec:
  selector:
    es-app: logstash
  ports:
    - port: 8080
EOF
```

volumes

```yaml
cat << 'EOF' >volumes.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
  namespace: es
spec:
  storageClassName: nfs
  nfs:
    path: /data/nfs-volume/logstash
    server: 10.0.0.20
  persistentVolumeReclaimPolicy: Recycle
  accessModes:
  - ReadWriteMany
  capacity:
    storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: logstash-conf-pvc
  namespace: es
spec:
  accessModes:
  - ReadWriteMany
  storageClassName: nfs
  resources:
    requests:
      storage: 1Gi
EOF
```

nfs主机上添加logstash配置文件

```json
cat << 'EOF' >/data/nfs-volume/logstash/logstash.conf
input {
  beats {
    port => 5044
  }
}
output {
  stdout {
    codec => rubydebug
  }
}
EOF
```

部署

```bash
kubectl apply -f volumes.yaml 
kubectl apply -f cm.yaml 
kubectl apply -f dp.yaml 
kubectl apply -f svc.yaml 
```

