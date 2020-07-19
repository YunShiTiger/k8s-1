### 1、部署nfs

略。。。

```bash
mkdir redis-cluster && cd redis-cluster
```

### 2、StorageClass创建

```yaml
cat<< 'EOF' >redis-cluster.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: redis-cluster-data
  namespace: infra
provisioner: fuseim.pri/ifs
EOF
```

### 3、创建ConfigMap

```yaml
cat<< 'EOF' >redis-cluster-configmap.yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: redis-cluster-config
  namespace: infra
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
data:
    redis-cluster.conf: |
      # 节点端口
      port 6379
      # 开启集群模式
      cluster-enabled yes
      # 节点超时时间，单位毫秒
      cluster-node-timeout 15000
      # 集群内部配置文件
      cluster-config-file "nodes.conf"
EOF
```

### 4、创建RBAC

```yaml
cat<< 'EOF' >redis-cluster-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: redis-cluster
  namespace: infra
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: redis-cluster
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
  name: redis-cluster
  namespace: infra
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: redis-cluster
subjects:
- kind: ServiceAccount
  name: redis-cluster
  namespace: infra
EOF
```

### 5、创建StatefulSet

```yaml
cat<< 'EOF' >redis-cluster-ss.yaml
kind: StatefulSet
apiVersion: apps/v1
metadata:
  labels:
    app: redis-cluster-ss
  name: redis-cluster-ss
  namespace: infra
spec:
  replicas: 6
  selector:
    matchLabels:
      app: redis-cluster-ss
  serviceName: redis-cluster-ss
  template:
    metadata:
      labels:
        app: redis-cluster-ss
    spec:
      containers:
      - args:
        - -c
        - cp /mnt/redis-cluster.conf /data ; redis-server /data/redis-cluster.conf
        command:
        - sh
        image: dotbalo/redis-trib:4.0.10
        imagePullPolicy: IfNotPresent
        name: redis-cluster
        ports:
        - containerPort: 6379
          name: masterport
          protocol: TCP
        volumeMounts:
        - mountPath: /mnt/
          name: config-volume
          readOnly: false
        - mountPath: /data/
          name: redis-cluster-storage
          readOnly: false
      serviceAccountName: redis-cluster
      terminationGracePeriodSeconds: 30
      volumes:
      - configMap:
          items:
          - key: redis-cluster.conf
            path: redis-cluster.conf
          name: redis-cluster-config 
        name: config-volume
  volumeClaimTemplates:
  - metadata:
      name: redis-cluster-storage
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: "redis-cluster-data"
      resources:
        requests:
          storage: 1Gi
EOF
```

### 6、创建Service

```yaml
cat<< 'EOF' >redis-cluster-service.yaml 
kind: Service
apiVersion: v1
metadata:
  labels:
    app: redis-cluster-ss
  name: redis-cluster-ss
  namespace: infra
spec:
  clusterIP: None
  ports:
  - name: redis
    port: 6379
    targetPort: 6379
  selector:
    app: redis-cluster-ss
EOF
```

### 7、应用资源清单

```
kubectl apply -f ./
```

查看状态

```
[root@manage redis-cluster]# kubectl get statefulset -n infra
NAME                         READY   AGE
redis-cluster-ss             3/6     2m6s
[root@manage redis-cluster]# kubectl get pod -n infra
NAME                             READY   STATUS    RESTARTS   AGE
redis-cluster-ss-0               1/1     Running   0          2m31s
redis-cluster-ss-1               1/1     Running   0          113s
redis-cluster-ss-2               1/1     Running   0          30s
redis-cluster-ss-3               1/1     Running   0          27s
redis-cluster-ss-4               1/1     Running   0          22s
redis-cluster-ss-5               1/1     Running   0          17s
[root@manage redis-cluster]# kubectl get svc -n infra
NAME                         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
redis-cluster-ss             ClusterIP   None           <none>        6379/TCP            2m56s
```

### 8、创建slot，初始化集群

````bash
# 等待所有pod启动完毕后，直接执行以下命令。
v=""
for i in `kubectl get po -n infra -l app=redis-cluster-ss -o wide | awk  '{print $6}' | grep -v IP`; do v="$v $i:6379";done
kubectl exec -ti redis-cluster-ss-5 -n infra -- redis-trib.rb create --replicas 1 $v
````

### 9、查看状态

集群nodes

````
[root@manage redis-cluster]# kubectl exec -ti redis-cluster-ss-0 -n infra -- redis-cli cluster nodes 
c08c4c3cfb6dcc3f74689f7664966a233a0352c3 172.16.90.215:6379@16379 slave 8b3075d19282599302f5c9bfe36c7db2ff9e0913 0 1595172528124 6 connected
307c81d0383caee89111da2bd53584b0ec296b0e 172.16.90.214:6379@16379 slave 51ba7e8d1d3d7cea8710d77d5322269a55cbe9e5 0 1595172529128 4 connected
c0b38f420aaffb3a6b574e8ea312edd4512508bc 172.16.42.196:6379@16379 myself,master - 0 1595172528000 1 connected 0-5460
8b3075d19282599302f5c9bfe36c7db2ff9e0913 172.16.90.213:6379@16379 master - 0 1595172529000 2 connected 5461-10922
b0cad4bf1277520db45a5358c8f2dc2343fbb1a7 172.16.42.198:6379@16379 slave c0b38f420aaffb3a6b574e8ea312edd4512508bc 0 1595172530131 5 connected
51ba7e8d1d3d7cea8710d77d5322269a55cbe9e5 172.16.42.197:6379@16379 master - 0 1595172527118 3 connected 10923-16383
````

集群信息

```
[root@manage redis-cluster]# kubectl exec -ti redis-cluster-ss-0 -n infra -- redis-cli cluster info
cluster_state:ok
cluster_slots_assigned:16384
cluster_slots_ok:16384
cluster_slots_pfail:0
cluster_slots_fail:0
cluster_known_nodes:6
cluster_size:3
cluster_current_epoch:6
cluster_my_epoch:1
cluster_stats_messages_ping_sent:332
cluster_stats_messages_pong_sent:344
cluster_stats_messages_sent:676
cluster_stats_messages_ping_received:339
cluster_stats_messages_pong_received:332
cluster_stats_messages_meet_received:5
cluster_stats_messages_received:676
```

### 10、暴露 TCP 服务

由于 Traefik 中使用 TCP 路由配置需要 SNI，而 SNI 又是依赖 TLS 的，所以我们需要配置证书才行，但是如果没有证书的话，我们可以使用通配符 `*` 进行配置，我们这里创建一个 IngressRouteTCP 类型的 CRD 对象（前面我们就已经安装了对应的 CRD 资源）：(ingressroute-redis.yaml)

```yaml
cat<< 'EOF' >redis-cluster.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRouteTCP
metadata:
  name: redis
  namespace: infra
spec:
  entryPoints:
    - redis
  routes:
  - match: HostSNI(`*`)
    services:
    - name: redis-cluster-ss
      port: 6379
EOF
kubectl apply -f redis-cluster.yaml
```

### 11、DNS解析Traefik 所在的节点

```bash
redis	60 IN A 10.0.0.50
```

### 12、测试访问(通过 6379 端口来连接 Redis 服务)

```csharp
[root@manage ~]# kubectl run  --rm -it redis --image=redis -- /bin/bash
If you don't see a command prompt, try pressing enter.
root@redis:/data# redis-cli -h redis.wzxmt.com -p 6379
redis.wzxmt.com:6379> 
```

### 13、测试主从切换

在K8S上搭建完好Redis集群后，我们最关心的就是其原有的高可用机制是否正常。这里，我们可以任意挑选一个Master的Pod来测试集群的主从切换机制，如`redis-cluster-ss-2`：

```csharp
[root@manage ~]# kubectl -n infra get pods -l app=redis-cluster-ss -o wide
NAME                 READY   STATUS    RESTARTS   AGE   IP           NODE   NOMINATED NODE   READINESS GATES
redis-cluster-ss-0   1/1     Running   0          21m   172.16.42.196   n1     <none>           <none>
redis-cluster-ss-1   1/1     Running   0          20m   172.16.90.213   n2     <none>           <none>
redis-cluster-ss-2   1/1     Running   0          19m   172.16.42.197   n1     <none>           <none>
redis-cluster-ss-3   1/1     Running   0          19m   172.16.90.214   n2     <none>           <none>
redis-cluster-ss-4   1/1     Running   0          18m   172.16.42.198   n1     <none>           <none>
redis-cluster-ss-5   1/1     Running   0          18m   172.16.90.215   n2     <none>           <none>
```

进入`redis-cluster-ss-2`查看：

```ruby
[root@manage ~]# kubectl -n infra exec -it redis-cluster-ss-2 -- redis-cli
127.0.0.1:6379> role
1) "master"
2) (integer) 1442
3) 1) 1) "172.16.90.214"
      2) "6379"
      3) "1442"
```

如上可以看到，其为master，slave为`172.16.90.214`即`redis-cluster-ss-3`。

接着，我们手动删除`redis-cluster-ss-2`：

```csharp
[root@manage ~]# kubectl -n infra delete pods redis-cluster-ss-2
pod "redis-cluster-ss-2" deleted
[root@manage ~]# kubectl -n infra get pods redis-cluster-ss-2 -o wide
NAME                 READY   STATUS    RESTARTS   AGE   IP           NODE  NOMINATED NODE   READINESS GATES
redis-cluster-ss-2   1/1     Running   0          6s   172.16.42.199   n1     <none>           <none>
```

如上，IP改变为`172.16.42.199`。我们再进入`redis-cluster-ss-2`内部查看：

```ruby
[root@manage ~]# kubectl -n infra exec -it redis-cluster-ss-2 -- redis-cli
127.0.0.1:6379> role
1) "master"
2) (integer) 98
3) 1) 1) "172.16.90.214"
      2) "6379"
      3) "98"
```

如上，`redis-cluster-ss-2`还是master，从属于它之前的从节点`172.16.90.214`即`redis-cluster-ss-3`。

### 14、其他说明

终止某一个pod虽然IP会变，但是不会影响集群完整性，会自我恢复。测试过终止所有Redis Cluster POD，此时集群无法正常恢复，使用failover.py会恢复集群，并且不会丢失已保存的数据。

```python
cat<< 'EOF' >failover.py 
#!/usr/bin/env python
import os,sys

def change_ip():
  id_data = {}
  new_data = {}
  for i in range(0,6):
    po_name = "redis-cluster-ss-%s" %i
    ID = os.popen("kubectl exec -ti %s -n infra -- grep 'myself' /data/nodes.conf | awk -F':' '{print $1}' | awk '{print $1}'" %po_name).read().split('\n')[0:-1][0]
    new_ip = os.popen("kubectl get pods %s -n infra -o wide | awk '{print $6}'| grep -v IP"%po_name).read().split('\n')[0:-1][0]
    id_data[po_name] = ID
    new_data[po_name] = new_ip
  
  for pod_name in id_data.keys():
      for pn in id_data.keys():
        print "%s -------------> %s"%(id_data[pn],new_data[pn])
        os.system("kubectl exec -ti {po_name} -n infra -- sed -i 's#{ID} \(.*\):6379#{ID} {new_ip}:6379#g' /data/nodes.conf".format(ID=id_data[pn], new_ip=new_data[pn], po_name=pod_name))
        print "replacing {ip} to {new_ip} in the nodes.conf of {po_name}".format(ip=id_data[pn], new_ip=new_data[pn], po_name=pod_name)
      
      print "restart redis..."
      os.system("kubectl exec -ti %s -n infra -- killall redis-server"%pod_name)

if __name__ == '__main__':
  run_number = os.popen("kubectl get po -n infra -o wide | grep -v READY | wc -l").read().split('\n')[0:-1][0]
  print "pod of running currently is %s" %run_number
  if run_number < 6:
    sys.exit("please wait for pod to start...")
  else:
    print "failover..."
  change_ip()
EOF
```

