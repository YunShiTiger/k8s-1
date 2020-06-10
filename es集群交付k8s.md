创建名称空间

```bash
kubectl create ns es
```

授权harbor仓库访问

```bash
kubectl create secret docker-registry harborlogin \
--namespace=es  \
--docker-server=https://harbor.wzxmt.com \
--docker-username=admin \
--docker-password=admin
```

RBAC授权

```yaml
cat<< 'EOF' > rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    elastic-app: elasticsearch
  name: es-admin
  namespace: es
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: elasticsearch-admin
  labels:
    elastic-app: elasticsearch
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: elasticsearch-admin
    namespace: es
EOF
```

StatefulSet(包含master与node)

```yaml
cat<< 'EOF' >es-dp.yaml
kind: StatefulSet
apiVersion: apps/v1
metadata:
  labels:
    app: elasticsearch
    role: master
  name: elasticsearch-master
  namespace: es
spec:
  volumeClaimTemplates:
  - metadata:
      name: es-master-storage
    spec:
      accessModes: 
      - ReadWriteOnce
      storageClassName: es-master
      resources:
        requests:
          storage: 10Gi
  replicas: 2
  serviceName: elasticsearch-master
  selector:
    matchLabels:
      app: elasticsearch
      role: master
  template:
    metadata:
      labels:
        app: elasticsearch
        role: master
    spec:
      restartPolicy: Always
      serviceAccountName: es-admin
      securityContext:
        fsGroup: 1000
      imagePullSecrets:
      - name: harborlogin
      containers:
        - name: elasticsearch-master
          image: harbor.wzxmt.com/infra/elasticsearch:7.1.0
          imagePullPolicy: IfNotPresent
          securityContext:
            privileged: true
          ports:
            - containerPort: 9200
              protocol: TCP
            - containerPort: 9200
              protocol: TCP
          volumeMounts:
          - name: es-master-storage
            mountPath: /usr/share/elasticsearch/data
          env:
            - name: cluster.name
              value: "es_cluster"
            - name: node.master
              value: "true"
            - name: node.data
              value: "false"
            - name: discovery.seed_hosts 
              value: "elasticsearch-discovery" 
            - name: cluster.initial_master_nodes 
              value: "elasticsearch-master-0,elasticsearch-master-1" 
            - name: node.ingest
              value: "false"
            - name: ES_JAVA_OPTS
              value: "-Xms1g -Xmx1g" 
---
kind: StatefulSet
apiVersion: apps/v1
metadata:
  labels:
    app: elasticsearch
    role: data
  name: elasticsearch-data
  namespace: es
spec:
  volumeClaimTemplates:
  - metadata:
      name: es-data-storage
    spec:
      accessModes: 
      - ReadWriteOnce
      storageClassName: es-data
      resources:
        requests:
          storage: 10Gi
  replicas: 2
  serviceName: elasticsearch-data
  selector:
    matchLabels:
      app: elasticsearch
      role: data
  template:
    metadata:
      labels:
        app: elasticsearch
        role: data
    spec:
      restartPolicy: Always
      serviceAccountName: es-admin
      securityContext:
        fsGroup: 1000
      imagePullSecrets:
      - name: harborlogin
      containers:
        - name: elasticsearch-data
          image: harbor.wzxmt.com/infra/elasticsearch:7.1.0
          imagePullPolicy: IfNotPresent
          securityContext:
            privileged: true
          ports:
            - containerPort: 9200
              protocol: TCP
            - containerPort: 9300
              protocol: TCP
          volumeMounts:
          - name: es-data-storage
            mountPath: /usr/share/elasticsearch/data
          env:
            - name: cluster.name
              value: "es_cluster"
            - name: node.master
              value: "false"
            - name: node.data
              value: "true"
            - name: discovery.seed_hosts
              value: "elasticsearch-discovery" 
            - name: cluster.initial_master_nodes 
              value: "elasticsearch-master-0,elasticsearch-master-1" 
            - name: node.ingest
              value: "false"
            - name: ES_JAVA_OPTS
              value: "-Xms1g -Xmx1g" 
EOF
```

SVC

```yaml
cat<< 'EOF' >svc.yaml
kind: Service
apiVersion: v1
metadata:
 labels:
   app: elasticsearch
 name: elasticsearch-discovery
 namespace: es
spec:
 ports:
   - port: 9300
     name: inner
   - port: 9200
     name: outer
 selector:
   app: elasticsearch
   role: master
---
apiVersion: v1
kind: Service
metadata:
 name: elasticsearch-data-service
 namespace: es
 labels:
   app: elasticsearch
   role: data
spec:
 ports:
   - port: 9200
     name: outer
   - port: 9300
     name: inner
 clusterIP: None
 selector:
   app: elasticsearch
   role: data
EOF
```

StorageClass

```yaml
cat<< 'EOF' >sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: es-data
  namespace: es
provisioner: fuseim.pri/ifs
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: es-master
  namespace: es
provisioner: fuseim.pri/ifs
EOF
```

节点优化（必须，要不然集群起不来）

添加下面四行内容：

```bash
cat<< 'EOF' >>/etc/security/limits.conf
* soft nofile 65536
* hard nofile 131072
* soft nproc 2048
* hard nproc 4096
EOF
```

打开文件vim /etc/sysctl.conf，添加下面一行内容：

```
echo "vm.max_map_count=262144" >>/etc/sysctl.conf
```

加载sysctl配置，执行命令：sysctl -p

查看es的service的IP：

```bash
[root@m1 ~]# kubectl -n es get svc
NAME                         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
elasticsearch-data-service   ClusterIP   None           <none>        9200/TCP,9300/TCP   24m
elasticsearch-discovery      ClusterIP   10.96.191.46   <none>        9300/TCP,9200/TCP   24m
```

查看集群master信息：

```bash
[root@m1 ~]# curl 10.96.191.46:9200/_cat/master?v
id                     host         ip           node
DolNio2RQKiZPARz9wH_Gw 10.96.31.232 10.96.31.232 elasticsearch-master-0
```


查看集群健康信息：

```bash
curl 10.96.191.46:9200/_cat/health?v
```


![image-20200610015440688](https://raw.githubusercontent.com/wzxmt/images/master/img/image-20200610015440688.png)

到此，es集群搭建成功！