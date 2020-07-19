## 1.创建NFS存储

```
mkdir redis && cd redis
```

略。。。。

## 2.创建StorageClass

```bash
cat<< 'EOF' >redis-sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: redis-data
  namespace: infra
provisioner: fuseim.pri/ifs
EOF
kubectl apply -f redis-sc.yaml
```

## 3.创建Configmap

Redis的配置文件转化为Configma

```csharp
cat << 'EOF' >cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:  
  name: redis-conf  
  namespace: infra
data:  
  redis.conf: |    
    appendonly yes
    cluster-enabled yes
    cluster-config-file /var/lib/redis/nodes.conf
    cluster-node-timeout 5000
    dir /var/lib/redis
    port 6379
EOF
kubectl apply -f cm.yaml
```

查看：

```swift
[root@manage redis]# kubectl -n infra describe cm redis-conf
Name:         redis-conf
Namespace:    infra
Labels:       <none>
Annotations:  
Data
====
redis.conf:
----
appendonly yes
cluster-enabled yes
cluster-config-file /var/lib/redis/nodes.conf
cluster-node-timeout 5000
dir /var/lib/redis
port 6379

Events:  <none>
```

## 4.创建Redis 集群节点

创建好Headless service后，就可以利用StatefulSet创建Redis 集群节点，这也是本文的核心内容。我们先创建redis.yml文件：

```yaml
cat << 'EOF' >sfs.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-app
  namespace: infra
spec:
  serviceName: "redis-service"
  replicas: 6
  selector:    
    matchLabels:      
        app: redis
        appCluster: redis-cluster
  template:
    metadata:
      labels:
        app: redis
        appCluster: redis-cluster
    spec:
      terminationGracePeriodSeconds: 20
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - redis
              topologyKey: kubernetes.io/hostname
      containers:
      - name: redis
        image: "redis"
        command:
          - "redis-server"
        args:
          - "/etc/redis/redis.conf"
          - "--protected-mode"
          - "no"
        resources:
          requests:
            cpu: "100m"
            memory: "100Mi"
        ports:
            - name: redis
              containerPort: 6379
              protocol: "TCP"
            - name: cluster
              containerPort: 16379
              protocol: "TCP"
        volumeMounts:
          - name: "redis-conf"
            mountPath: "/etc/redis"
          - name: redis-data-storage
            mountPath: "/var/lib/redis"
      volumes:
      - name: "redis-conf"
        configMap:
          name: "redis-conf"
          items:
            - key: "redis.conf"
              path: "redis.conf"
  volumeClaimTemplates:
  - metadata:
      name: redis-data-storage
    spec:
      accessModes: 
      - ReadWriteMany
      storageClassName: redis-data
      resources:
        requests:
          storage: 1Gi
EOF
```

如上，总共创建了6个Redis节点(Pod)，其中3个将用于master，另外3个分别作为master的slave；Redis的配置通过volume将之前生成的`redis-conf`这个Configmap，挂载到了容器的`/etc/redis/redis.conf`；Redis的数据存储路径使用volumeClaimTemplates声明（也就是PVC），其会绑定到自动创建的PV上。

pod AntiAffinity表示反亲和性，其决定了某个pod不可以和哪些Pod部署在同一拓扑域，可以用于将一个服务的POD分散在不同的主机或者拓扑域中，提高服务本身的稳定性。

而PreferredDuringSchedulingIgnoredDuringExecution 则表示，在调度期间尽量满足亲和性或者反亲和性规则，如果不能满足规则，POD也有可能被调度到对应的主机上。在之后的运行过程中，系统不会再检查这些规则是否满足。

在这里，matchExpressions规定了Redis Pod要尽量不要调度到包含app为redis的Node上，也即是说已经存在Redis的Node上尽量不要再分配Redis Pod了。但是，由于我们只有三个Node，而副本有6个，因此根据PreferredDuringSchedulingIgnoredDuringExecution，这些豌豆不得不得挤一挤，挤挤更健康~

另外，根据StatefulSet的规则，我们生成的Redis的6个Pod的hostname会被依次命名为$(statefulset名称)-$(序号)，如下图所示：

```csharp
[root@manage redis]# kubectl get pod -n infra 
NAME                             READY   STATUS    RESTARTS   AGE
redis-app-0                      1/1     Running   0          12m
redis-app-1                      1/1     Running   0          12m
redis-app-2                      1/1     Running   0          11m
redis-app-3                      1/1     Running   0          11m
redis-app-4                      1/1     Running   0          11m
redis-app-5                      1/1     Running   0          10m
```

如上，可以看到这些Pods在部署时是以{0..N-1}的顺序依次创建的。注意，直到redis-app-0状态启动后达到Running状态之后，redis-app-1 才开始启动。

同时，每个Pod都会得到集群内的一个DNS域名，格式为`$(podname).$(service name).$(namespace).svc.cluster.local`，也即是：

```css
redis-app-0.redis-service.infra.svc.cluster.local
redis-app-1.redis-service.infra.svc.cluster.local
...以此类推...
```

在K8S集群内部，这些Pod就可以利用该域名互相通信。我们可以使用busybox镜像的nslookup检验这些域名：

## 5.创建svc

```yaml
cat << 'EOF' >>svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-service
  namespace: infra
  labels:
    app: redis
spec:
  ports:
  - name: redis-port
    port: 6379
  clusterIP: None
  selector:
    app: redis
    appCluster: redis-cluster
EOF
kubectl apply -f svc.yaml
```

查看：

```bash
[root@manage redis]# kubectl get svc -n infra redis-service
NAME            TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
redis-service   ClusterIP   None         <none>        6379/TCP   11s
```

可以看到，服务名称为`redis-service`，其`CLUSTER-IP`为`None`，表示这是一个“无头”服务。

## 5.初始化Redis集群

创建好6个Redis Pod后，我们还需要利用常用的Redis-tribe工具进行集群的初始化。

由于Redis集群必须在所有节点启动后才能进行初始化，而如果将初始化逻辑写入Statefulset中，则是一件非常复杂而且低效的行为。也就是说，我们可以在K8S上创建一个额外的容器，专门用于进行K8S集群内部某些服务的管理控制。

这里，我们专门启动一个Ubuntu的容器，可以在该容器中安装Redis-tribe，进而初始化Redis集群，执行：

```undefined
kubectl run  --rm -it ubuntu --image=ubuntu -- /bin/bash
```

成功后，我们可以进入ubuntu容器中

修改源：

```tsx
cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/ubuntu/ bionic main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ bionic main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ bionic-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ bionic-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ bionic-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ bionic-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ bionic-proposed main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ bionic-proposed main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ bionic-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ bionic-backports main restricted universe multiverse
EOF
```

安装基本的软件环境：

```
apt-get update
apt-get install -y vim wget python2.7 python-pip redis-tools dnsutils
```

## 6.初始化集群

首先，我们需要安装`redis-trib`：

```undefined
pip install redis-trib
```

然后，创建只有Master节点的集群：

```css
redis-trib.py create \
  `dig +short redis-app-0.redis-service.infra.svc.cluster.local`:6379 \
  `dig +short redis-app-1.redis-service.infra.svc.cluster.local`:6379 \
  `dig +short redis-app-2.redis-service.infra.svc.cluster.local`:6379
```

如上，命令`dig +short redis-app-0.redis-service.infra.svc.cluster.local`用于将Pod的域名转化为IP，这是因为`redis-trib`不支持域名来创建集群。

其次，为每个Master添加Slave：

```css
redis-trib.py replicate \
  --master-addr `dig +short redis-app-0.redis-service.infra.svc.cluster.local`:6379 \
  --slave-addr `dig +short redis-app-3.redis-service.infra.svc.cluster.local`:6379

redis-trib.py replicate \
  --master-addr `dig +short redis-app-1.redis-service.infra.svc.cluster.local`:6379 \
  --slave-addr `dig +short redis-app-4.redis-service.infra.svc.cluster.local`:6379

redis-trib.py replicate \
  --master-addr `dig +short redis-app-2.redis-service.infra.svc.cluster.local`:6379 \
  --slave-addr `dig +short redis-app-5.redis-service.infra.svc.cluster.local`:6379
```

至此，我们的Redis集群就真正创建完毕了，连到任意一个Redis Pod中检验一下：

```shell
[root@manage redis]# kubectl -n infra exec -it redis-app-2 /bin/bash 
kubectl exec [POD] [COMMAND] is DEPRECATED and will be removed in a future version. Use kubectl kubectl exec [POD] -- [COMMAND] instead.
root@redis-app-2:/data# redis-cli -c
127.0.0.1:6379> cluster nodes
11c6f4539965e3b8bc847cd5234ac979d96b7479 172.16.90.155:6379@16379 slave c2fa361e6752720a894541d3a75167a9246fcd46 0 1594974536083 5 connected
a3afe9aec264e103479a864747c097dd61e222c8 172.16.90.153:6379@16379 master - 0 1594974535080 2 connected 5462-10922
d35f0220c7193550ca441fda6bd682cb9881e91b 172.16.42.168:6379@16379 slave 11deb82668991e7af66238cb9d4dbd29c1d2d7bc 0 1594974535582 1 connected
c2fa361e6752720a894541d3a75167a9246fcd46 172.16.42.166:6379@16379 master - 0 1594974534000 5 connected 10923-16383
11deb82668991e7af66238cb9d4dbd29c1d2d7bc 172.16.90.154:6379@16379 myself,master - 0 1594974535000 1 connected 0-5461
0e2f179de835254238323c30a908dd96565b95d6 172.16.42.167:6379@16379 slave a3afe9aec264e103479a864747c097dd61e222c8 0 1594974534579 3 connected
127.0.0.1:6379> cluster info
cluster_state:ok
cluster_slots_assigned:16384
cluster_slots_ok:16384
cluster_slots_pfail:0
cluster_slots_fail:0
cluster_known_nodes:6
cluster_size:3
cluster_current_epoch:5
cluster_my_epoch:1
cluster_stats_messages_ping_sent:477
cluster_stats_messages_pong_sent:473
cluster_stats_messages_meet_sent:1
cluster_stats_messages_sent:951
cluster_stats_messages_ping_received:471
cluster_stats_messages_pong_received:478
cluster_stats_messages_meet_received:2
cluster_stats_messages_received:951
```

另外，还可以在NFS上查看Redis挂载的数据：

```csharp
[root@manage StorageClass]# ll infra-redis-data-storage-redis-app-0-pvc-50c9bd6b-f485-48f7-9115-e85c627038de
total 8
-rw-r--r-- 1 root root   0 Jul 17 15:58 appendonly.aof
-rw-r--r-- 1 root root 175 Jul 17 16:27 dump.rdb
-rw-r--r-- 1 root root 805 Jul 17 16:27 nodes.conf
```

## 7.暴露 TCP 服务

由于 Traefik 中使用 TCP 路由配置需要 SNI，而 SNI 又是依赖 TLS 的，所以我们需要配置证书才行，但是如果没有证书的话，我们可以使用通配符 `*` 进行配置，我们这里创建一个 IngressRouteTCP 类型的 CRD 对象（前面我们就已经安装了对应的 CRD 资源）：(ingressroute-redis.yaml)

```yaml
cat<< 'EOF' >ingress-redis.yaml
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
    - name: redis-service
      port: 6379
EOF
kubectl apply -f  ingress-redis.yaml
```

## 8.DNS解析Traefik 所在的节点

```bash
redis	60 IN A 10.0.0.50
```

## 9.测试访问(通过 6379 端口来连接 Redis 服务)

```csharp
[root@manage ~]# kubectl run  --rm -it redis --image=redis -- /bin/bash
If you don't see a command prompt, try pressing enter.
root@redis:/data# redis-cli -h redis.wzxmt.com -p 6379
redis.wzxmt.com:6379> 
```

## 10.测试主从切换

在K8S上搭建完好Redis集群后，我们最关心的就是其原有的高可用机制是否正常。这里，我们可以任意挑选一个Master的Pod来测试集群的主从切换机制，如`redis-app-2`：

```csharp
[root@manage ~]# kubectl -n infra get pods -l app=redis -o wide
NAME          READY   STATUS    RESTARTS   AGE    IP              NODE   NOMINATED NODE   READINESS GATES
redis-app-0   1/1     Running   0          119m   172.16.90.153   n2     <none>           <none>
redis-app-1   1/1     Running   0          119m   172.16.42.166   n1     <none>           <none>
redis-app-2   1/1     Running   0          118m   172.16.90.154   n2     <none>           <none>
redis-app-3   1/1     Running   0          118m   172.16.42.167   n1     <none>           <none>
redis-app-4   1/1     Running   0          118m   172.16.90.155   n2     <none>           <none>
redis-app-5   1/1     Running   0          117m   172.16.42.168   n1     <none>           <none>
```

进入`redis-app-2`查看：

```ruby
[root@manage ~]# kubectl -n infra exec -it redis-app-2 /bin/bash
root@redis-app-2:/data# redis-cli -c
127.0.0.1:6379> role
1) "master"
2) (integer) 7644
3) 1) 1) "172.16.42.168"
      2) "6379"
      3) "7644"
```

如上可以看到，其为master，slave为`172.16.42.168`即`redis-app-5`。

接着，我们手动删除`redis-app-2`：

```csharp
[root@manage ~]# kubectl -n infra delete pods redis-app-2
pod "redis-app-2" deleted
[root@manage ~]# kubectl -n infra get pods redis-app-2 -o wide
NAME          READY   STATUS    RESTARTS   AGE   IP              NODE   NOMINATED NODE   READINESS GATES
redis-app-2   1/1     Running   0          12s   172.16.90.171   n2     <none>           <none>
```

如上，IP改变为`172.16.90.171`。我们再进入`redis-app-2`内部查看：

```ruby
[root@manage ~]# kubectl -n infra exec -it redis-app-2 /bin/bash
root@redis-app-2:/data# redis-cli -c
127.0.0.1:6379> role
1) "slave"
2) "172.16.42.168"
3) (integer) 6379
4) "connected"
5) (integer) 7910
```

如上，`redis-app-2`变成了slave，从属于它之前的从节点`172.16.42.168`即`redis-app-5`。

## 11.疑问

至此，大家可能会疑惑，前面讲了这么多似乎并没有体现出StatefulSet的作用，其提供的稳定标志`redis-app-*`仅在初始化集群的时候用到，而后续Redis Pod的通信或配置文件中并没有使用该标志。我想说，是的，本文使用StatefulSet部署Redis确实没有体现出其优势，还不如介绍Zookeeper集群来的明显，不过没关系，学到知识就好。

那为什么没有使用稳定的标志，Redis Pod也能正常进行故障转移呢？这涉及了Redis本身的机制。因为，Redis集群中每个节点都有自己的NodeId（保存在自动生成的`nodes.conf`中），并且该NodeId不会随着IP的变化和变化，这其实也是一种固定的网络标志。也就是说，就算某个Redis Pod重启了，该Pod依然会加载保存的NodeId来维持自己的身份。我们可以在NFS上查看`redis-app-1`的`nodes.conf`文件：

```ruby
[root@manage ~]# cat /data/nfs-volume/StorageClass/infra-redis-data-storage-redis-app-0-pvc-50c9bd6b-f485-48f7-9115-e85c627038de/nodes.conf 
d35f0220c7193550ca441fda6bd682cb9881e91b 172.16.42.168:6379@16379 master - 0 1594980099000 6 connected 0-5461
11c6f4539965e3b8bc847cd5234ac979d96b7479 172.16.90.155:6379@16379 slave c2fa361e6752720a894541d3a75167a9246fcd46 0 1594980100000 5 connected
a3afe9aec264e103479a864747c097dd61e222c8 172.16.90.153:6379@16379 myself,master - 0 1594980100000 2 connected 5462-10922
0e2f179de835254238323c30a908dd96565b95d6 172.16.42.167:6379@16379 slave a3afe9aec264e103479a864747c097dd61e222c8 0 1594980100609 3 connected
c2fa361e6752720a894541d3a75167a9246fcd46 172.16.42.166:6379@16379 master - 0 1594980100000 5 connected 10923-16383
11deb82668991e7af66238cb9d4dbd29c1d2d7bc 172.16.90.171:6379@16379 slave d35f0220c7193550ca441fda6bd682cb9881e91b 0 1594980101011 6 connected
vars currentEpoch 6 lastVoteEpoch 6
```

如上，第一列为NodeId，稳定不变；第二列为IP和端口信息，可能会改变。

这里，我们介绍NodeId的两种使用场景：

- 当某个Slave Pod断线重连后IP改变，但是Master发现其NodeId依旧， 就认为该Slave还是之前的Slave。
- 当某个Master Pod下线后，集群在其Slave中选举重新的Master。待旧Master上线后，集群发现其NodeId依旧，会让旧Master变成新Master的slave。

对于这两种场景，大家有兴趣的话还可以自行测试，注意要观察Redis的日志。