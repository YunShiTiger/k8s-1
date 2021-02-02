7、持久化数据备份和恢复

 etcd v2 和 v3 的数据不能混合存放，默认是v2。以下是v2的备份和恢复方法，v3参考 [etcd集群备份和数据恢复](https://my.oschina.net/u/2306127/blog/2986736)

测试数据

```bash
写入数据
ETCDCTL_API=2 etcdctl \
--ca-file /etc/kubernetes/pki/ca.pem \
--cert-file /etc/kubernetes/pki/etcd.pem \
--key-file /etc/kubernetes/pki/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
set /test wzxmt
读取API 2写入数据
ETCDCTL_API=2 etcdctl \
--ca-file /etc/kubernetes/pki/ca.pem \
--cert-file /etc/kubernetes/pki/etcd.pem \
--key-file /etc/kubernetes/pki/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
get /test
```

7.1备份

```bash
ETCDCTL_API=2 etcdctl backup --data-dir /data/etcd/data/ -backup-dir etcd_backup
tar -zcvf backup.etcd.tar.gz etcd_backup
```

7.2恢复

将backup.etcd.tar.gz copy到要恢复的集群任意一个服务器上，集群默认配置为1中的配置，将第一个恢复的服务器的ETCD_INITIAL_CLUSTER_STATE设置为new，其他两个设置为exsiting

```bash
tar -xvf backup.etcd.tar.gz
rm -rf /data/etcd/data
mv etcd_backup /data/etcd/data
```

7.3强制拉起一个etcd

```bash
etcd -data-dir=/data/etcd/data --name=etcd-m1 --force-new-cluster
```

 第一个窗口ctrl c,关闭当前节点

7.4启动当前节点

```bash
systemctl daemon-reload && systemctl restart etcd.service 
```

查看数据

```bash
ETCDCTL_API=2 etcdctl \
--ca-file /etc/kubernetes/pki/ca.pem \
--cert-file /etc/kubernetes/pki/etcd.pem \
--key-file /etc/kubernetes/pki/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
get /test
```

查看节点id 

```bash
[root@m1 ~]# etcdctl member list
7763ba8f3601, started, etcd-m1, http://localhost:2380, https://10.0.0.31:2379, false
```

 修改peerURL

```bash
[root@m1 ~]# curl http://localhost:2379/v2/members/7763ba8f3601 -XPUT -H "Content-Type:application/json" -d '{"peerURLs":["https://10.0.0.31:2380"]}'

[root@m1 ~]# etcdctl member list
7763ba8f3601, started, etcd-m1, https://10.0.0.31:2380, https://10.0.0.31:2379, false
```

7.5添加节点（ip为第二个服务器ip）

```bash
[root@m1 ~]# etcdctl member add etcd-m2 --peer-urls=https://10.0.0.32:2380
Member f1bc007d404a1fee added to cluster     7763ba8f3602

ETCD_NAME="etcd-m2"
ETCD_INITIAL_CLUSTER="etcd-m1=https://10.0.0.31:2380,etcd-m2=http://10.0.0.32:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.0.0.32:2380"
ETCD_INITIAL_CLUSTER_STATE="existing"

[root@m1 ~]# etcdctl member list
7763ba8f3601, started, etcd-m1, https://10.0.0.31:2380, https://10.0.0.31:2379, false
f1bc007d404a1fee, unstarted, , http://10.0.0.32:2380, , false
```

7.6启动第二个节点

更新/usr//lib/systemd/system/etcd.service的配置

```bash
--initial-cluster etcd-m1=https://10.0.0.31:2380,etcd-m2=https://10.0.0.32:2380
--initial-cluster-state=existing 
```

启动

```bash
rm -rf /data/etcd/data
systemctl daemon-reload && systemctl start etcd
```

7.7启动第三个节点

```bash
[root@m1 ~]# etcdctl member add etcd-m3 --peer-urls=https://10.0.0.33:2380
Member 1ffab5c9fbd3e060 added to cluster     7763ba8f3602

ETCD_NAME="etcd-m3"
ETCD_INITIAL_CLUSTER="etcd-m1=https://10.0.0.31:2380,etcd-m3=https://10.0.0.33:2380,etcd-m2=https://10.0.0.32:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://10.0.0.33:2380"
ETCD_INITIAL_CLUSTER_STATE="existing"
[root@m1 ~]# etcdctl member list
7763ba8f3601, started, etcd-m1, https://10.0.0.31:2380, https://10.0.0.31:2379, false
1ffab5c9fbd3e060, unstarted, , https://10.0.0.33:2380, , false
bd44b980d536ebb1, started, etcd-m2, https://10.0.0.32:2380, https://10.0.0.32:2379, false
```

更新/usr//lib/systemd/system/etcd.service的配置

```bash
--initial-cluster etcd-m1=https://10.0.0.31:2380,etcd-m2=https://10.0.0.32:2380,etcd-m3=https://10.0.0.33:2380
--initial-cluster-state=existing 
```

启动

```bash
rm -rf /data/etcd/data
systemctl daemon-reload && systemctl start etcd
```

查看节点id 

```bash
[root@m1 ~]# etcdctl member list
7763ba8f3601, started, etcd-m1, https://10.0.0.31:2380, https://10.0.0.31:2379, false
1ffab5c9fbd3e060, started, etcd-m3, https://10.0.0.33:2380, https://10.0.0.33:2379, false
bd44b980d536ebb1, started, etcd-m2, https://10.0.0.32:2380, https://10.0.0.32:2379, false
```

做好数据验证，如没问题，将所有节点的ETCD_INITIAL_CLUSTER更新为3个节点的，然后重启。