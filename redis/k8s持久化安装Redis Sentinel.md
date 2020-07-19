# k8s持久化安装Redis Sentinel

### 1、部署nfs

略。。。

```bash
mkdir redis-sentinel && cd redis-sentinel
```

### 2、StorageClass创建

```yaml
cat<< 'EOF' >redis-sentinel.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: redis-sentinel-data
  namespace: infra
provisioner: fuseim.pri/ifs
EOF
kubectl apply -f redis-sentinel.yaml
```

### 3、创建ConfigMap

　　Redis配置按需修改，默认使用的是rdb存储模式

```yaml
cat<< 'EOF' >redis-sentinel-configmap.yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: redis-sentinel-config
  namespace: infra
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
data:
    redis-master.conf: |
      port 6379
      tcp-backlog 511
      timeout 0
      tcp-keepalive 0
      loglevel notice
      databases 16
      save 900 1
      save 300 10
      save 60 10000
      stop-writes-on-bgsave-error yes
      rdbcompression yes
      rdbchecksum yes
      dbfilename dump.rdb
      dir /data/
      slave-serve-stale-data yes
      repl-diskless-sync no
      repl-diskless-sync-delay 5
      repl-disable-tcp-nodelay no
      slave-priority 100
      appendonly no
      appendfilename "appendonly.aof"
      appendfsync everysec
      no-appendfsync-on-rewrite no
      auto-aof-rewrite-percentage 100
      auto-aof-rewrite-min-size 64mb
      aof-load-truncated yes
      lua-time-limit 5000
      slowlog-log-slower-than 10000
      slowlog-max-len 128
      latency-monitor-threshold 0
      notify-keyspace-events ""
      hash-max-ziplist-entries 512
      hash-max-ziplist-value 64
      list-max-ziplist-entries 512
      list-max-ziplist-value 64
      set-max-intset-entries 512
      zset-max-ziplist-entries 128
      zset-max-ziplist-value 64
      hll-sparse-max-bytes 3000
      activerehashing yes
      client-output-buffer-limit normal 0 0 0
      client-output-buffer-limit slave 256mb 64mb 60
      client-output-buffer-limit pubsub 64mb 16mb 60
      hz 10
      aof-rewrite-incremental-fsync yes
    redis-slave.conf: |
      port 6379
      slaveof redis-sentinel-master-ss-0.redis-sentinel-master-ss.infra.svc.cluster.local 6379
      tcp-backlog 511
      timeout 0
      tcp-keepalive 0
      loglevel notice
      databases 16
      save 900 1
      save 300 10
      save 60 10000
      stop-writes-on-bgsave-error yes
      rdbcompression yes
      rdbchecksum yes
      dbfilename dump.rdb
      dir /data/
      slave-serve-stale-data yes
      slave-read-only yes
      repl-diskless-sync no
      repl-diskless-sync-delay 5
      repl-disable-tcp-nodelay no
      slave-priority 100
      appendonly no
      appendfilename "appendonly.aof"
      appendfsync everysec
      no-appendfsync-on-rewrite no
      auto-aof-rewrite-percentage 100
      auto-aof-rewrite-min-size 64mb
      aof-load-truncated yes
      lua-time-limit 5000
      slowlog-log-slower-than 10000
      slowlog-max-len 128
      latency-monitor-threshold 0
      notify-keyspace-events ""
      hash-max-ziplist-entries 512
      hash-max-ziplist-value 64
      list-max-ziplist-entries 512
      list-max-ziplist-value 64
      set-max-intset-entries 512
      zset-max-ziplist-entries 128
      zset-max-ziplist-value 64
      hll-sparse-max-bytes 3000
      activerehashing yes
      client-output-buffer-limit normal 0 0 0
      client-output-buffer-limit slave 256mb 64mb 60
      client-output-buffer-limit pubsub 64mb 16mb 60
      hz 10
      aof-rewrite-incremental-fsync yes
    redis-sentinel.conf: |
      port 26379
      dir /data
      sentinel monitor mymaster redis-sentinel-master-ss-0.redis-sentinel-master-ss.infra.svc.cluster.local 6379 2
      sentinel down-after-milliseconds mymaster 30000
      sentinel parallel-syncs mymaster 1
      sentinel failover-timeout mymaster 180000
EOF
kubectl apply -f redis-sentinel-configmap.yaml
```

　　注意，此时configmap中redis-slave.conf的slaveof的master地址为ss里面的Headless Service地址。

### 4、创建service

　　service主要提供pods之间的互访，StatefulSet主要用Headless Service通讯，格式：statefulSetName-{0..N-1}.serviceName.namespace.svc.cluster.local

　　- serviceName为Headless Service的名字

　　- 0..N-1为Pod所在的序号，从0开始到N-1

　　- statefulSetName为StatefulSet的名字

　　- namespace为服务所在的namespace，Headless Servic和StatefulSet必须在相同的namespace

　　- .cluster.local为Cluster Domain

master

```yaml
cat<< 'EOF' >redis-sentinel-service-master.yaml
kind: Service
apiVersion: v1
metadata:
  labels:
    app: redis-sentinel-master-ss
  name: redis-sentinel-master-ss
  namespace: infra
spec:
  clusterIP: None
  ports:
  - name: redis
    port: 6379
    targetPort: 6379
  selector:
    app: redis-sentinel-master-ss
EOF
kubectl apply -f redis-sentinel-service-master.yaml 
```

slave

```yaml
cat<< 'EOF' >redis-sentinel-service-slave.yaml
kind: Service
apiVersion: v1
metadata:
  labels:
    app: redis-sentinel-slave-ss
  name: redis-sentinel-slave-ss
  namespace: infra
spec:
  clusterIP: None
  ports:
  - name: redis
    port: 6379
    targetPort: 6379
  selector:
    app: redis-sentinel-slave-ss
EOF
kubectl apply -f redis-sentinel-service-slave.yaml
```

查看状态

```bash
[root@manage redis-sentinel]# kubectl get svc -n infra
NAME                       TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
redis-sentinel-master-ss   ClusterIP   None           <none>        6379/TCP            26m
redis-sentinel-slave-ss    ClusterIP   None           <none>        6379/TCP            26m
```

### 5、创建StatefulSet

rbac

```yaml
cat<< 'EOF' >redis-sentinel-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: redis-sentinel
  namespace: infra
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: redis-sentinel
  namespace: infra
rules:
  - apiGroups:
      - ""
    resources:
      - endpoints
    verbs:
      - get
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: redis-sentinel
  namespace: infra
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: redis-sentinel
subjects:
- kind: ServiceAccount
  name: redis-sentinel
  namespace: infra
EOF
```

StatefulSet-Master

```yaml
cat<< 'EOF' >redis-sentinel-ss-master.yaml
kind: StatefulSet
apiVersion: apps/v1
metadata:
  labels:
    app: redis-sentinel-master-ss
  name: redis-sentinel-master-ss
  namespace: infra
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-sentinel-master-ss
  serviceName: redis-sentinel-master-ss
  template:
    metadata:
      labels:
        app: redis-sentinel-master-ss
    spec:
      containers:
      - args:
        - -c
        - cp /mnt/redis-master.conf /data/ ; redis-server /data/redis-master.conf
        command:
        - sh
        image: redis
        imagePullPolicy: IfNotPresent
        name: redis-master
        ports:
        - containerPort: 6379
          name: masterport
          protocol: TCP
        volumeMounts:
        - mountPath: /mnt/
          name: config-volume
          readOnly: false
        - mountPath: /data/
          name: redis-sentinel-master-storage
          readOnly: false
      serviceAccountName: redis-sentinel
      terminationGracePeriodSeconds: 30
      volumes:
      - configMap:
          items:
          - key: redis-master.conf
            path: redis-master.conf
          name: redis-sentinel-config 
        name: config-volume
  volumeClaimTemplates:
  - metadata:
      name: redis-sentinel-master-storage
    spec:
      accessModes:
      - ReadWriteMany
      storageClassName: "redis-sentinel-data"
      resources:
        requests:
          storage: 4Gi
EOF
```

StatefulSet-Slave

```yaml
cat<< 'EOF' >redis-sentinel-ss-slave.yaml
kind: StatefulSet
apiVersion: apps/v1
metadata:
  labels:
    app: redis-sentinel-slave-ss
  name: redis-sentinel-slave-ss
  namespace: infra
spec:
  replicas: 2
  selector:
    matchLabels:
      app: redis-sentinel-slave-ss
  serviceName: redis-sentinel-slave-ss
  template:
    metadata:
      labels:
        app: redis-sentinel-slave-ss
    spec:
      containers:
      - args:
        - -c
        - cp /mnt/redis-slave.conf /data/ ; redis-server /data/redis-slave.conf
        command:
        - sh
        image: redis
        imagePullPolicy: IfNotPresent
        name: redis-slave
        ports:
        - containerPort: 6379
          name: slaveport
          protocol: TCP
        volumeMounts:
        - mountPath: /mnt/
          name: config-volume
          readOnly: false
        - mountPath: /data/
          name: redis-sentinel-slave-storage
          readOnly: false
      serviceAccountName: redis-sentinel
      terminationGracePeriodSeconds: 30
      volumes:
      - configMap:
          items:
          - key: redis-slave.conf
            path: redis-slave.conf
          name: redis-sentinel-config 
        name: config-volume
  volumeClaimTemplates:
  - metadata:
      name: redis-sentinel-slave-storage
    spec:
      accessModes:
      - ReadWriteMany
      storageClassName: "redis-sentinel-data"
      resources:
        requests:
          storage: 4Gi
EOF
```

应用资源清单

```
kubectl apply -f redis-sentinel-rbac.yaml -f redis-sentinel-ss-master.yaml -f redis-sentinel-ss-slave.yaml
```

查看状态

```bash
[root@manage redis-sentinel]#  kubectl get statefulset -n infra
NAME                       READY   AGE
redis-sentinel-master-ss   1/1     72s
redis-sentinel-slave-ss    2/2     72s
[root@manage redis-sentinel]#  kubectl get pods -n infra
NAME                             READY   STATUS    RESTARTS   AGE
redis-sentinel-master-ss-0       1/1     Running   0          2m1s
redis-sentinel-slave-ss-0        1/1     Running   0          2m1s
redis-sentinel-slave-ss-1        1/1     Running   0          119s
[root@manage redis-cluster]# kubectl get svc -n infra
NAME                         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
redis-sentinel-master-ss     ClusterIP   None           <none>        6379/TCP            95m
redis-sentinel-sentinel-ss   ClusterIP   None           <none>        26379/TCP           53m
redis-sentinel-slave-ss      ClusterIP   None           <none>        6379/TCP            95m
```

　　此时相当于已经在k8s上创建了Redis的主从模式。

### 6、pods通讯测试

master连接slave测试

```bash
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-master-ss-0 -n infra -- redis-cli -h redis-sentinel-slave-ss-0.redis-sentinel-slave-ss.infra.svc.cluster.local ping
PONG
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-master-ss-0 -n infra -- redis-cli -h redis-sentinel-slave-ss-1.redis-sentinel-slave-ss.infra.svc.cluster.local  ping
PONG
```

slave连接master测试

```bash
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-slave-ss-0 -n infra -- redis-cli -h redis-sentinel-master-ss-0.redis-sentinel-master-ss.infra.svc.cluster.local  ping
PONG
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-slave-ss-1 -n infra -- redis-cli -h redis-sentinel-master-ss-0.redis-sentinel-master-ss.infra.svc.cluster.local  ping
PONG
```

### 7、状态查看

同步状态

```bash
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-slave-ss-1 -n infra -- redis-cli -h redis-sentinel-master-ss-0.redis-sentinel-master-ss.infra.svc.cluster.local  info replication
# Replication
role:master
connected_slaves:2
slave0:ip=172.16.42.191,port=6379,state=online,offset=756,lag=0
slave1:ip=172.16.90.210,port=6379,state=online,offset=756,lag=0
master_replid:b98b6a9230152caa99d72b98a99087f37d2f3cf1
master_replid2:0000000000000000000000000000000000000000
master_repl_offset:756
second_repl_offset:-1
repl_backlog_active:1
repl_backlog_size:1048576
repl_backlog_first_byte_offset:1
repl_backlog_histlen:756
```

　同步测试

```bash
# master写入数据
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-slave-ss-1 -n infra -- redis-cli -h redis-sentinel-master-ss-0.redis-sentinel-master-ss.infra.svc.cluster.local  set test test_data
OK
# master获取数据
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-slave-ss-1 -n infra -- redis-cli -h redis-sentinel-master-ss-0.redis-sentinel-master-ss.infra.svc.cluster.local  get test
"test_data"
# slave获取数据
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-slave-ss-1 -n infra -- redis-cli   get test
"test_data"
```

　　从节点无法写入数据

```bash
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-slave-ss-1 -n infra -- redis-cli   set k v
(error) READONLY You can't write against a read only replica.
```

　　NFS查看数据存储

```bash
[root@manage infra-redis-sentinel-master-storage-redis-sentinel-master-ss-0-pvc-84879199-e425-434b-959d-56e2c2fdbf28]# ls
dump.rdb  redis-master.conf
```

　　说明：个人认为在k8s上搭建Redis sentinel完全没有意义，经过测试，当master节点宕机后，sentinel选择新的节点当主节点，当原master恢复后，此时无法再次成为集群节点。因为在物理机上部署时，sentinel探测以及更改配置文件都是以IP的形式，集群复制也是以IP的形式，但是在容器中，虽然采用的StatefulSet的Headless Service来建立的主从，但是主从建立后，master、slave、sentinel记录还是解析后的IP，但是pod的IP每次重启都会改变，所有sentinel无法识别宕机后又重新启动的master节点，所以一直无法加入集群，虽然可以通过固定podIP或者使用NodePort的方式来固定，或者通过sentinel获取当前master的IP来修改配置文件，但是个人觉得也是没有必要的，sentinel实现的是高可用Redis主从，检测Redis Master的状态，进行主从切换等操作，但是在k8s中，无论是dc或者ss，都会保证pod以期望的值进行运行，再加上k8s自带的活性检测，当端口不可用或者服务不可用时会自动重启pod或者pod的中的服务，所以当在k8s中建立了Redis主从同步后，相当于已经成为了高可用状态，并且sentinel进行主从切换的时间不一定有k8s重建pod的时间快，所以个人认为在k8s上搭建sentinel没有意义。所以下面搭建sentinel的步骤无需在看。 

### 8、创建sentinel

StatefulSet

```yaml
cat<< 'EOF' >redis-sentinel-ss-sentinel.yaml
kind: StatefulSet
apiVersion: apps/v1
metadata:
  labels:
    app: redis-sentinel-sentinel-ss
  name: redis-sentinel-sentinel-ss
  namespace: infra
spec:
  replicas: 3
  selector:
    matchLabels:
      app: redis-sentinel-sentinel-ss
  serviceName: redis-sentinel-sentinel-ss
  template:
    metadata:
      labels:
        app: redis-sentinel-sentinel-ss
    spec:
      containers:
      - args:
        - -c
        - cp /mnt/redis-sentinel.conf /data/ ; redis-sentinel /data/redis-sentinel.conf
        command:
        - sh
        image: redis
        imagePullPolicy: IfNotPresent
        name: redis-sentinel
        ports:
        - containerPort: 26379
          name: sentinel-port
          protocol: TCP
        volumeMounts:
        - mountPath: /mnt/
          name: config-volume
          readOnly: false
      serviceAccountName: redis-sentinel
      terminationGracePeriodSeconds: 30
      volumes:
      - configMap:
          items:
          - key: redis-sentinel.conf
            path: redis-sentinel.conf
          name: redis-sentinel-config 
        name: config-volume
EOF
```

Service

```yaml
cat<< 'EOF' >redis-sentinel-service-sentinel.yaml
kind: Service
apiVersion: v1
metadata:
  labels:
    app: redis-sentinel-sentinel-ss
  name: redis-sentinel-sentinel-ss
  namespace: infra
spec:
  clusterIP: None
  ports:
  - name: redis
    port: 26379
    targetPort: 26379
  selector:
    app: redis-sentinel-sentinel-ss
EOF
```

引用资源清单

```bash
kubectl create -f redis-sentinel-ss-sentinel.yaml -f redis-sentinel-service-sentinel.yaml
```

查看状态

```bash
[root@manage redis-sentinel]# kubectl get service -n infra
NAME                         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
redis-sentinel-master-ss     ClusterIP   None           <none>        6379/TCP            43m
redis-sentinel-sentinel-ss   ClusterIP   None           <none>        26379/TCP           58s
redis-sentinel-slave-ss      ClusterIP   None           <none>        6379/TCP            43m
[root@manage redis-sentinel]# kubectl get statefulset -n infra
NAME                         READY   AGE
redis-sentinel-master-ss     1/1     35m
redis-sentinel-sentinel-ss   3/3     113s
redis-sentinel-slave-ss      2/2     35m
[root@manage redis-sentinel]# kubectl get pods -n infra
NAME                             READY   STATUS    RESTARTS   AGE
redis-sentinel-master-ss-0       1/1     Running   0          36m
redis-sentinel-sentinel-ss-0     1/1     Running   0          2m22s
redis-sentinel-sentinel-ss-1     1/1     Running   0          2m21s
redis-sentinel-sentinel-ss-2     1/1     Running   0          2m19s
redis-sentinel-slave-ss-0        1/1     Running   0          36m
redis-sentinel-slave-ss-1        1/1     Running   0          36m
```

### 9、查看哨兵状态

```bash
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-sentinel-ss-0 -n infra -- redis-cli -h 127.0.0.1 -p 26379 info Sentinel
# Sentinel
sentinel_masters:1
sentinel_tilt:0
sentinel_running_scripts:0
sentinel_scripts_queue_length:0
sentinel_simulate_failure_flags:0
master0:name=mymaster,status=ok,address=172.16.42.190:6379,slaves=2,sentinels=3
```

### 10、容灾测试

```bash
# 查看当前数据
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-master-ss-0 -n infra -- redis-cli -h 127.0.0.1 -p 6379 get test
"test_data"
```

　　关闭master节点

```bash
[root@manage redis-sentinel]# kubectl -n infra scale StatefulSet redis-sentinel-master-ss --replicas=0
statefulset.apps/redis-sentinel-master-ss scaled
```

　　查看状态

```bash
[root@manage redis-sentinel]# kubectl get pods -n infra
NAME                             READY   STATUS    RESTARTS   AGE
redis-sentinel-sentinel-ss-0     1/1     Running   0          6m26s
redis-sentinel-sentinel-ss-1     1/1     Running   0          6m25s
redis-sentinel-sentinel-ss-2     1/1     Running   0          6m23s
redis-sentinel-slave-ss-0        1/1     Running   0          40m
redis-sentinel-slave-ss-1        1/1     Running   0          40m
```

　　查看sentinel状态

```bash
[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-sentinel-ss-2 -n infra -- redis-cli -h 127.0.0.1 -p 26379 info Sentinel
# Sentinel
sentinel_masters:1
sentinel_tilt:0
sentinel_running_scripts:0
sentinel_scripts_queue_length:0
sentinel_simulate_failure_flags:0
master0:name=mymaster,status=ok,address=172.16.90.210:6379,slaves=2,sentinels=3

[root@manage redis-sentinel]# kubectl exec -ti redis-sentinel-slave-ss-0 -n infra -- redis-cli -h 127.0.0.1 -p 6379 info replication
# Replication
role:slave
master_host:172.16.90.210
master_port:6379
master_link_status:up
master_last_io_seconds_ago:1
master_sync_in_progress:0
slave_repl_offset:89623
slave_priority:100
slave_read_only:1
connected_slaves:0
master_replid:b1f338be63287912031017027ac96f2c7cda2215
master_replid2:b98b6a9230152caa99d72b98a99087f37d2f3cf1
master_repl_offset:89623
second_repl_offset:78110
repl_backlog_active:1
repl_backlog_size:1048576
repl_backlog_first_byte_offset:1
repl_backlog_histlen:89623
```

