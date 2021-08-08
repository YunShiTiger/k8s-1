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

```
mkdir -p minio && cd minio
```

StorageClass

```yaml
cat << 'EOF' >sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: minio-data
provisioner: fuseim.pri/ifs
EOF
```

cm

```yaml
cat << 'EOF' >configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: minio
  labels:
    app: minio
    version: minio-8.0.10
data:
  initialize: |-
    #!/bin/sh
    set -e ; # Have script exit in the event of a failed command.
    MC_CONFIG_DIR="/etc/minio/mc/"
    MC="/usr/bin/mc --insecure --config-dir ${MC_CONFIG_DIR}"

    # connectToMinio
    # Use a check-sleep-check loop to wait for Minio service to be available
    connectToMinio() {
      SCHEME=$1
      ATTEMPTS=0 ; LIMIT=29 ; # Allow 30 attempts
      set -e ; # fail if we can't read the keys.
      ACCESS=$(cat /config/accesskey) ; SECRET=$(cat /config/secretkey) ;
      set +e ; # The connections to minio are allowed to fail.
      echo "Connecting to Minio server: $SCHEME://$MINIO_ENDPOINT:$MINIO_PORT" ;
      MC_COMMAND="${MC} config host add myminio $SCHEME://$MINIO_ENDPOINT:$MINIO_PORT $ACCESS $SECRET" ;
      $MC_COMMAND ;
      STATUS=$? ;
      until [ $STATUS = 0 ]
      do
        ATTEMPTS=`expr $ATTEMPTS + 1` ;
        echo \"Failed attempts: $ATTEMPTS\" ;
        if [ $ATTEMPTS -gt $LIMIT ]; then
          exit 1 ;
        fi ;
        sleep 2 ; # 1 second intervals between attempts
        $MC_COMMAND ;
        STATUS=$? ;
      done ;
      set -e ; # reset `e` as active
      return 0
    }

    # checkBucketExists ($bucket)
    # Check if the bucket exists, by using the exit code of `mc ls`
    checkBucketExists() {
      BUCKET=$1
      CMD=$(${MC} ls myminio/$BUCKET > /dev/null 2>&1)
      return $?
    }

    # createBucket ($bucket, $policy, $purge)
    # Ensure bucket exists, purging if asked to
    createBucket() {
      BUCKET=$1
      POLICY=$2
      PURGE=$3
      VERSIONING=$4

      # Purge the bucket, if set & exists
      # Since PURGE is user input, check explicitly for `true`
      if [ $PURGE = true ]; then
        if checkBucketExists $BUCKET ; then
          echo "Purging bucket '$BUCKET'."
          set +e ; # don't exit if this fails
          ${MC} rm -r --force myminio/$BUCKET
          set -e ; # reset `e` as active
        else
          echo "Bucket '$BUCKET' does not exist, skipping purge."
        fi
      fi

      # Create the bucket if it does not exist
      if ! checkBucketExists $BUCKET ; then
        echo "Creating bucket '$BUCKET'"
        ${MC} mb myminio/$BUCKET
      else
        echo "Bucket '$BUCKET' already exists."
      fi


      # set versioning for bucket
      if [ ! -z $VERSIONING ] ; then
        if [ $VERSIONING = true ] ; then
            echo "Enabling versioning for '$BUCKET'"
            ${MC} version enable myminio/$BUCKET
        elif [ $VERSIONING = false ] ; then
            echo "Suspending versioning for '$BUCKET'"
            ${MC} version suspend myminio/$BUCKET
        fi
      else
          echo "Bucket '$BUCKET' versioning unchanged."
      fi

      # At this point, the bucket should exist, skip checking for existence
      # Set policy on the bucket
      echo "Setting policy of bucket '$BUCKET' to '$POLICY'."
      ${MC} policy set $POLICY myminio/$BUCKET
    }

    # Try connecting to Minio instance
    scheme=http
    connectToMinio $scheme
EOF
```

secrets

```yaml
cat << EOF >secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: minio
  namespace: minio
  labels:
    app: minio
    version: minio-8.0.10   
type: Opaque
data:
  accesskey: "$(echo -n "admin" | base64)"
  secretkey: "$(echo -n "admin123" | base64)"
EOF
```

StatefulSet

```yaml
cat << 'EOF' >sf.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: minio
  labels:
    app: minio
    version: minio-8.0.10   
spec:
  updateStrategy:
    type: RollingUpdate
  podManagementPolicy: "Parallel"
  serviceName: minio-svc
  replicas: 4
  selector:
    matchLabels:
      app: minio
      version: minio-8.0.10
  template:
    metadata:
      name: minio
      labels:
        app: minio
        version: minio-8.0.10
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: minio
          image: minio/minio
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
EOF
```

svc

```yaml
cat << 'EOF' >svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio
  labels:
    app: minio
    version: minio-8.0.10
spec:
  ports:
    - name: http
      port: 9000
      protocol: TCP
  selector:
    app: minio
    version: minio-8.0.10
---
apiVersion: v1
kind: Service
metadata:
  name: minio-svc
  namespace: minio
  labels:
    app: minio
    version: minio-8.0.10   
spec:
  clusterIP: None
  ports:
    - name: http
      port: 9000
      protocol: TCP
  selector:
    app: minio
    version: minio-8.0.10
EOF
```

IngressRoute

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
    - name: minio-svc
      port: 9000
EOF
```

