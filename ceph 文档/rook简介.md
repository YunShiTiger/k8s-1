## rook简介

Rook官网：[https://rook.io](https://rook.io/)
**容器的持久化存储**
容器的持久化存储是保存容器存储状态的重要手段，存储插件会在容器里挂载一个基于网络或者其他机制的远程数据卷，使得在容器里创建的文件，实际上是保存在远程存储服务器上，或者以分布式的方式保存在多个节点上，而与当前宿主机没有任何绑定关系。这样，无论你在其他哪个宿主机上启动新的容器，都可以请求挂载指定的持久化存储卷，从而访问到数据卷里保存的内容。
由于 Kubernetes 本身的松耦合设计，绝大多数存储项目，比如 Ceph、GlusterFS、NFS 等，都可以为 Kubernetes 提供持久化存储能力。
**Ceph分布式存储系统**
Ceph是一种高度可扩展的分布式存储解决方案，提供对象、文件和块存储。在每个存储节点上，您将找到Ceph存储对象的文件系统和Ceph OSD（对象存储守护程序）进程。在Ceph集群上，您还可以找到Ceph MON（监控）守护程序，它们确保Ceph集群保持高可用性。
**Rook**
Rook 是一个开源的cloud-native storage编排, 提供平台和框架；为各种存储解决方案提供平台、框架和支持，以便与云原生环境本地集成。
Rook 将存储软件转变为自我管理、自我扩展和自我修复的存储服务，它通过自动化部署、引导、配置、置备、扩展、升级、迁移、灾难恢复、监控和资源管理来实现此目的。
Rook 使用底层云本机容器管理、调度和编排平台提供的工具来实现它自身的功能。
Rook 目前支持Ceph、NFS、Minio Object Store和CockroachDB。

Rook使用Kubernetes原语使Ceph存储系统能够在Kubernetes上运行。下图说明了Ceph Rook如何与Kubernetes集成：
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190104133544110.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L25ldHdvcmtlbg==,size_16,color_FFFFFF,t_70)
随着Rook在Kubernetes集群中运行，Kubernetes应用程序可以挂载由Rook管理的块设备和文件系统，或者可以使用S3 / Swift API提供对象存储。Rook oprerator自动配置存储组件并监控群集，以确保存储处于可用和健康状态。
Rook oprerator是一个简单的容器，具有引导和监视存储集群所需的全部功能。oprerator将启动并监控ceph monitor pods和OSDs的守护进程，它提供基本的RADOS存储。oprerator通过初始化运行服务所需的pod和其他组件来管理池，对象存储（S3 / Swift）和文件系统的CRD。
oprerator将监视存储后台驻留程序以确保群集正常运行。Ceph mons将在必要时启动或故障转移，并在群集增长或缩小时进行其他调整。oprerator还将监视api服务请求的所需状态更改并应用更改。
Rook oprerator还创建了Rook agent。这些agent是在每个Kubernetes节点上部署的pod。每个agent都配置一个Flexvolume插件，该插件与Kubernetes的volume controller集成在一起。处理节点上所需的所有存储操作，例如附加网络存储设备，安装卷和格式化文件系统。
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190104133558632.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L25ldHdvcmtlbg==,size_16,color_FFFFFF,t_70)
该rook容器包括所有必需的Ceph守护进程和工具来管理和存储所有数据 - 数据路径没有变化。 rook并没有试图与Ceph保持完全的忠诚度。 许多Ceph概念（如placement groups和crush maps）都是隐藏的，因此您无需担心它们。 相反，Rook为管理员创建了一个简化的用户体验，包括物理资源，池，卷，文件系统和buckets。 同时，可以在需要时使用Ceph工具应用高级配置。
Rook在golang中实现。Ceph在C ++中实现，其中数据路径被高度优化。我们相信这种组合可以提供两全其美的效果。

## 部署环境准备

**官方参考：**
root项目地址：https://github.com/rook/rook
rook官方参考文档：https://rook.io/docs/rook/v1.4/quickstart.html

**kubernetes集群准备**
集群节点信息：略

在集群中至少有三个节点可用，满足ceph高可用要求，这里已配置master节点使其支持运行pod。

**rook使用存储方式**
rook默认使用所有节点的所有资源，rook operator自动在所有节点上启动OSD设备，Rook会用如下标准监控并发现可用设备：

- 设备没有分区
- 设备没有格式化的文件系统

Rook不会使用不满足以上标准的设备。另外也可以通过修改配置文件，指定哪些节点或者设备会被使用。
**添加新磁盘**
这里在所有节点添加1块50GB的新磁盘：/dev/sdb，作为OSD盘，提供存储空间，添加完成后扫描磁盘，确保主机能够正常识别到：

```shell
#扫描 SCSI总线并添加 SCSI 设备
for host in $(ls /sys/class/scsi_host) ; do echo "- - -" > /sys/class/scsi_host/$host/scan; done

#重新扫描 SCSI 总线
for scsi_device in $(ls /sys/class/scsi_device/); do echo 1 > /sys/class/scsi_device/$scsi_device/device/rescan; done

#查看已添加的磁盘，能够看到sdb说明添加成功
lsblk
```

本次搭建的基本原理图：
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190106123334504.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L25ldHdvcmtlbg==,size_16,color_FFFFFF,t_70)
无另外说明，以下全部操作都在master节点执行。

## 部署Rook Operator

克隆rook github仓库到本地

```shell
git clone --single-branch --branch v1.4.4 https://github.com/rook/rook.git
cd rook/cluster/examples/kubernetes/ceph
```

执行yaml文件部署rook系统组件：

```shell
kubectl create -f common.yaml
kubectl create -f operator.yaml
```

如上所示，它会创建如下资源：

1. namespace：rook-ceph，之后的所有rook相关的pod都会创建在该namespace下面
2. CRD：创建五个CRDs，.ceph.rook.io
3. role & clusterrole：用户资源控制
4. serviceaccount：ServiceAccount资源，给Rook创建的Pod使用
5. deployment：rook-ceph-operator，部署rook ceph相关的组件

部署rook-ceph-operator过程中，会触发以DaemonSet的方式在集群部署Agent和Discoverpods。
operator会在集群内的每个主机创建两个pod:rook-discover,rook-ceph-agent：

## 创建rook Cluster

当检查到Rook operator, agent, and discover pods已经是running状态后，就可以部署root cluster了。
执行yaml文件结果：

```shell
kubectl apply -f cluster.yaml 
```

如上所示，它会创建如下资源：

1. namespace：rook-ceph，之后的所有Ceph集群相关的pod都会创建在该namespace下
2. serviceaccount：ServiceAccount资源，给Ceph集群的Pod使用
3. role & rolebinding：用户资源控制
4. cluster：rook-ceph，创建的Ceph集群

Ceph集群部署成功后，可以查看到的pods如下，其中osd数量取决于你的节点数量：

```shell
[root@m1 ~]# kubectl get pod -n rook-ceph -o wide
NAME                                 READY   STATUS        RESTARTS   AGE     IP            NODE   NOMINATED NODE   READINESS GATES
rook-ceph-detect-version-w9f55       0/1     Pending       0          2m12s   <none>        n2     <none>   
rook-ceph-mgr-a-785c69855f-7rkp6     1/1     Running       0          76s     10.96.5.13    n3     <none>   
rook-ceph-mgr-a-785c69855f-g4mkg     1/1     Terminating   15         60m     10.96.48.21   n2     <none>   
rook-ceph-mgr-a-785c69855f-pr6sl     1/1     Running       9          53m     10.96.5.12    n3     <none>   
rook-ceph-mon-a-85bfcb8448-spk26     1/1     Running       0          73m     10.96.5.8     n3     <none>   
rook-ceph-operator-db86d47f5-lmbt8   1/1     Running       3          115m    10.96.5.5     n3     <none>   
rook-ceph-osd-0-69c66457f5-nfdbz     1/1     Running       0          71m     10.96.5.10    n3     <none>   
rook-ceph-osd-1-775f6c64bb-zbgdx     1/1     Running       0          71m     10.96.41.39   n1     <none>   
rook-ceph-osd-2-7f6959f94c-crl8j     1/1     Running       0          70m     10.96.48.20   n2     <none>   
rook-ceph-osd-prepare-n1-pljnj       0/1     Completed     0          72m     10.96.41.38   n1     <none>   
rook-ceph-osd-prepare-n2-z68xr       0/1     Completed     0          72m     10.96.48.19   n2     <none>   
rook-ceph-osd-prepare-n3-c664w       0/1     Completed     1          72m     10.96.5.9     n3     <none>   
rook-discover-kblr9                  1/1     Running       0          113m    10.96.41.27   n1     <none>   
rook-discover-w2rrs                  1/1     Running       3          113m    10.96.48.12   n2     <none>   
```

可以看出部署的Ceph集群有：

1. Ceph Monitors：默认启动三个ceph-mon，可以在cluster.yaml里配置
2. Ceph Mgr：默认启动一个，可以在cluster.yaml里配置
3. Ceph OSDs：根据cluster.yaml里的配置启动，默认在所有的可用节点上启动
   上述Ceph组件对应kubernetes的kind是deployment：

```shell
[root@m1 ~]# kubectl -n rook-ceph get deployment
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
rook-ceph-mgr-a      2/2     2            2           71m
rook-ceph-mon-a      1/1     1            1           73m
rook-ceph-operator   1/1     1            1           115m
rook-ceph-osd-0      1/1     1            1           71m
rook-ceph-osd-1      1/1     1            1           71m
rook-ceph-osd-2      0/1     1            0           70m
```

**删除Ceph集群**
如果要删除已创建的Ceph集群，可执行下面命令：

```shell
# kubectl delete -f cluster.yaml
```

删除Ceph集群后，在之前部署Ceph组件节点的/var/lib/rook/目录，会遗留下Ceph集群的配置信息。
若之后再部署新的Ceph集群，先把之前Ceph集群的这些信息删除，不然启动monitor会失败；

```shell
# cat clean-rook-dir.sh
hosts=(
  n1
  n2
  n3
)
for host in ${hosts[@]} ; do
  ssh $host "rm -rf /var/lib/rook/*"
done
```

## 配置ceph dashboard

在cluster.yaml文件中默认已经启用了ceph dashboard，查看dashboard的service：

```shell
[root@m1 ~]# kubectl get service -n rook-ceph
NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
rook-ceph-mgr             ClusterIP   10.96.114.155   <none>        9283/TCP            70m
rook-ceph-mgr-dashboard   ClusterIP   10.96.77.75     <none>        7000/TCP            70m
rook-ceph-mon-a           ClusterIP   10.96.252.33    <none>        6789/TCP,3300/TCP   72m
```

rook-ceph-mgr-dashboard监听的端口是8443，创建nodeport类型的service以便集群外部访问。

```shell
kubectl apply -f rook/cluster/examples/kubernetes/ceph/dashboard-external-https.yaml
```

查看一下nodeport暴露的端口，这里是32483端口：

```shell
[root@m1 ~]# kubectl get service -n rook-ceph | grep dashboard
rook-ceph-mgr-dashboard                  ClusterIP   10.96.77.75     <none>        7000/TCP            74m
rook-ceph-mgr-dashboard-external-https   NodePort    10.96.18.201    <none>        8443:29150/TCP      11s
```

登录信息
连接到仪表板后，您将需要登录以安全访问。Rook 在运行Rook Ceph集群的名称空间中创建一个默认用户， admin并生成一个称为的秘密rook-ceph-dashboard-admin-password。要检索生成的密码，可以运行以下命令：

```shell
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo
```

找到username和password字段，我这里是admin，8v2AbqHDj6
打开浏览器输入任意一个Node的IP+nodeport端口，这里使用master节点 ip访问：
[https://192.168.92.56:32483](https://192.168.92.56:32483/)
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190104134300431.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L25ldHdvcmtlbg==,size_16,color_FFFFFF,t_70)
登录后界面如下：
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190104134335201.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L25ldHdvcmtlbg==,size_16,color_FFFFFF,t_70)
查看hosts状态：
运行了1个mgr、3个mon和3个osd
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190104134341810.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L25ldHdvcmtlbg==,size_16,color_FFFFFF,t_70)
查看monitors状态：
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190104134348345.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L25ldHdvcmtlbg==,size_16,color_FFFFFF,t_70)
查看OSD状态
3个osd状态正常，每个容量50GB.
![在这里插入图片描述](https://img-blog.csdnimg.cn/2019010413440155.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L25ldHdvcmtlbg==,size_16,color_FFFFFF,t_70)

## 部署Ceph toolbox

默认启动的Ceph集群，是开启Ceph认证的，这样你登陆Ceph组件所在的Pod里，是没法去获取集群状态，以及执行CLI命令，这时需要部署Ceph toolbox，命令如下：

```shell
kubectl apply -f rook/cluster/examples/kubernetes/ceph/toolbox.yaml
```

部署成功后，pod如下：

```shell
[root@m1 ceph]$  kubectl -n rook-ceph get pods -o wide | grep ceph-tools
rook-ceph-tools-76c7d559b6-8w7bk         1/1     Running     0          11s     192.168.92.58   k8s-node2    <none>           <none>
```

然后可以登陆该pod后，执行Ceph CLI命令：

```shell
[root@m1 ceph]$ kubectl -n rook-ceph exec -it rook-ceph-tools-76c7d559b6-8w7bk bash
bash: warning: setlocale: LC_CTYPE: cannot change locale (en_US.UTF-8): No such file or directory
bash: warning: setlocale: LC_COLLATE: cannot change locale (en_US.UTF-8): No such file or directory
bash: warning: setlocale: LC_MESSAGES: cannot change locale (en_US.UTF-8): No such file or directory
bash: warning: setlocale: LC_NUMERIC: cannot change locale (en_US.UTF-8): No such file or directory
bash: warning: setlocale: LC_TIME: cannot change locale (en_US.UTF-8): No such file or directory
```

查看ceph集群状态

```shell
[root@k8s-node2 /]# ceph status
  cluster:
    id:     abddff95-5fa0-47dc-a001-7fb291a42bc6
    health: HEALTH_OK
 
  services:
    mon: 3 daemons, quorum c,b,a
    mgr: a(active)
    osd: 3 osds: 3 up, 3 in
 
  data:
    pools:   1 pools, 100 pgs
    objects: 0  objects, 0 B
    usage:   12 GiB used, 129 GiB / 141 GiB avail
    pgs:     100 active+clean
```

查看ceph配置文件

```shell
[root@k8s-node2 /]# cd /etc/ceph/
[root@k8s-node2 ceph]# ll
total 12
-rw-r--r-- 1 root root 121 Jan  3 11:28 ceph.conf
-rw-r--r-- 1 root root  62 Jan  3 11:28 keyring
-rw-r--r-- 1 root root  92 Sep 24 18:15 rbdmap
[root@k8s-node2 ceph]# cat ceph.conf 
[global]
mon_host = 10.104.1.238:6790,10.105.153.93:6790,10.105.107.254:6790

[client.admin]
keyring = /etc/ceph/keyring
[root@k8s-node2 ceph]# cat keyring
[client.admin]
key = AQBjoC1cXKJ7KBAA3ZnhWyxvyGa8+fnLFK7ykw==
[root@k8s-node2 ceph]# cat rbdmap 
# RbdDevice             Parameters
#poolname/imagename     id=client,keyring=/etc/ceph/ceph.client.keyring
[root@k8s-node2 ceph]# 
12345678910111213141516171819
```

## rook提供RBD服务

rook可以提供以下3类型的存储：
 Block: Create block storage to be consumed by a pod
 Object: Create an object store that is accessible inside or outside the Kubernetes cluster
 Shared File System: Create a file system to be shared across multiple pods
在提供（Provisioning）块存储之前，需要先创建StorageClass和存储池。K8S需要这两类资源，才能和Rook交互，进而分配持久卷（PV）。
在kubernetes集群里，要提供rbd块设备服务，需要有如下步骤：

1. 创建rbd-provisioner pod
2. 创建rbd对应的storageclass
3. 创建pvc，使用rbd对应的storageclass
4. 创建pod使用rbd pvc

通过rook创建Ceph Cluster之后，rook自身提供了rbd-provisioner服务，所以我们不需要再部署其provisioner。
备注：代码位置pkg/operator/ceph/provisioner/provisioner.go
**创建pool和StorageClass**
查看storageclass.yaml的配置（默认）：

```yaml
[root@m1 ~]$ vim rook/cluster/examples/kubernetes/ceph/storageclass.yaml
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: replicapool
  namespace: rook-ceph
spec:
  replicated:
    size: 1
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: rook-ceph-block
provisioner: ceph.rook.io/block
parameters:
  blockPool: replicapool
  # Specify the namespace of the rook cluster from which to create volumes.
  # If not specified, it will use `rook` as the default namespace of the cluster.
  # This is also the namespace where the cluster will be
  clusterNamespace: rook-ceph
  # Specify the filesystem type of the volume. If not specified, it will use `ext4`.
  fstype: xfs
  # (Optional) Specify an existing Ceph user that will be used for mounting storage with this StorageClass.
  #mountUser: user1
  # (Optional) Specify an existing Kubernetes secret name containing just one key holding the Ceph user secret.
  # The secret must exist in each namespace(s) where the storage will be consumed.
  #mountSecret: ceph-user1-secret
12345678910111213141516171819202122232425262728
```

配置文件中包含了一个名为replicapool的存储池，和名为rook-ceph-block的storageClass。

运行yaml文件

```shell
kubectl apply -f /rook/cluster/examples/kubernetes/ceph/storageclass.yaml
```

查看创建的storageclass:

```shell
[root@m1 ~]$ kubectl get storageclass
NAME              PROVISIONER          AGE
rook-ceph-block   ceph.rook.io/block   171m
[root@m1 ~]$ 
1234
```

登录ceph dashboard查看创建的存储池：
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190104134752317.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L25ldHdvcmtlbg==,size_16,color_FFFFFF,t_70)
**使用存储**
以官方wordpress示例为例，创建一个经典的wordpress和mysql应用程序来使用Rook提供的块存储，这两个应用程序都将使用Rook提供的block volumes。
查看yaml文件配置，主要看定义的pvc和挂载volume部分，以wordpress.yaml为例：

```yaml
[root@m1 ~]$ cat rook/cluster/examples/kubernetes/wordpress.yaml 
......
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wp-pv-claim
  labels:
    app: wordpress
spec:
  storageClassName: rook-ceph-block
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
......
        volumeMounts:
        - name: wordpress-persistent-storage
          mountPath: /var/www/html
      volumes:
      - name: wordpress-persistent-storage
        persistentVolumeClaim:
          claimName: wp-pv-claim
```

yaml文件里定义了一个名为wp-pv-claim的pvc，指定storageClassName为rook-ceph-block，申请的存储空间大小为20Gi。最后一部分创建了一个名为wordpress-persistent-storage的volume，并且指定 claimName为pvc的名称，最后将volume挂载到pod的/var/lib/mysql目录下。
启动mysql和wordpress ：

```shell
kubectl apply -f rook/cluster/examples/kubernetes/mysql.yaml
kubectl apply -f rook/cluster/examples/kubernetes/wordpress.yaml
```

这2个应用都会创建一个块存储卷，并且挂载到各自的pod中，查看声明的pvc和pv：

```shell
[root@m1 ~]$ kubectl get pvc
NAME             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS      AGE
mysql-pv-claim   Bound    pvc-5bfbe28e-0fc9-11e9-b90d-000c291c25f3   20Gi       RWO            rook-ceph-block   32m
wp-pv-claim      Bound    pvc-5f56c6d6-0fc9-11e9-b90d-000c291c25f3   20Gi       RWO            rook-ceph-block   32m
[root@m1 ~]$ kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                    STORAGECLASS      REASON   AGE
pvc-5bfbe28e-0fc9-11e9-b90d-000c291c25f3   20Gi       RWO            Delete           Bound    default/mysql-pv-claim   rook-ceph-block            32m
pvc-5f56c6d6-0fc9-11e9-b90d-000c291c25f3   20Gi       RWO            Delete           Bound    default/wp-pv-claim      rook-ceph-block            32m
[root@m1 ~]$ 
123456789
```

注意：这里的pv会自动创建，当提交了包含 StorageClass 字段的 PVC 之后，Kubernetes 就会根据这个 StorageClass 创建出对应的 PV，这是用到的是Dynamic Provisioning机制来动态创建pv，PV 支持 Static 静态请求，和动态创建两种方式。
在Ceph集群端检查：

```shell
[root@m1 ceph]$ kubectl -n rook-ceph exec -it rook-ceph-tools-76c7d559b6-8w7bk bash
......
[root@k8s-node2 /]# rbd info -p replicapool pvc-5bfbe28e-0fc9-11e9-b90d-000c291c25f3 
rbd image 'pvc-5bfbe28e-0fc9-11e9-b90d-000c291c25f3':
        size 20 GiB in 5120 objects
        order 22 (4 MiB objects)
        id: 88156b8b4567
        block_name_prefix: rbd_data.88156b8b4567
        format: 2
        features: layering
        op_features: 
        flags: 
        create_timestamp: Fri Jan  4 02:35:12 2019
```

登陆pod检查rbd设备：

```shell
[root@m1 ~]$ kubectl get pod -o wide
NAME                               READY   STATUS    RESTARTS   AGE    IP            NODE        NOMINATED NODE   READINESS GATES
wordpress-7b6c4c79bb-t5pst         1/1     Running   0          135m   10.244.1.16   k8s-node1   <none>           <none>
wordpress-mysql-6887bf844f-9pmg8   1/1     Running   0          135m   10.244.2.14   k8s-node2   <none>           <none>
[root@m1 ~]$ 

[root@m1 ~]$ kubectl exec -it wordpress-7b6c4c79bb-t5pst bash
root@wordpress-7b6c4c79bb-t5pst:/var/www/html#
root@wordpress-7b6c4c79bb-t5pst:/var/www/html#  mount | grep rbd
/dev/rbd0 on /var/www/html type xfs (rw,relatime,attr2,inode64,sunit=8192,swidth=8192,noquota)
root@wordpress-7b6c4c79bb-t5pst:/var/www/html# df -h
Filesystem               Size  Used Avail Use% Mounted on
......
/dev/rbd0                 20G   59M   20G   1% /var/www/html
......
```

登录ceph dashboard查看创建的images
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190104134923802.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L25ldHdvcmtlbg==,size_16,color_FFFFFF,t_70)
一旦wordpress和mysql pods处于运行状态，获取wordpress应用程序的集群IP并使用浏览器访问：

```shell
[root@m1 ~]$ kubectl get svc wordpress
NAME        TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
wordpress   LoadBalancer   10.98.178.189   <pending>     80:30001/TCP   136m
```

访问wordpress:
![在这里插入图片描述](https://img-blog.csdnimg.cn/20190104135002395.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L25ldHdvcmtlbg==,size_16,color_FFFFFF,t_70)