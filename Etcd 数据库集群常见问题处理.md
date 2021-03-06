[ETCD](https://etcd.io/docs/v3.4.0/demo/#auth)是一个高可用的分布式Key/Value存储系统。它使用Raft算法，通过选举来保持集群内各节点状态的一致性。虽然ETCD具有高可用的特点，但是也无法避免多个节点宕机，甚至全部宕机的情况发生。如何快速的恢复集群，就变得格外重要。本文将介绍在日常工作中，遇到的ETCD集群常见问题的处理方法。

# 一、etcd常用命令

## 1、集群部署常用

```bash
export ETCD_SSL=/etc/kubernetes/pki
export ENDPOINTS="https://10.0.0.31:2379,https://10.0.0.32:2379,https://10.0.0.33:2379"
```

查看集群

```
etcdctl member list  
```

查看集群健康状态

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
endpoint health
```

查看集群状态

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} endpoint status --write-out=table
```

## 2、用户操作常用

### user相关命令

#### 1.1. 添加root用户并设置密码

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
user add root
```

#### 1.2. 添加非root用户并设置密码

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin user add coredns
```

#### 1.3. 查看当前所有用户

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin user list
```

#### 1.4. 将用户添加到对应角色

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin user grant-role coredns role01 
```

#### 1.5. 查看用户拥有哪些角色

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin user get coredns
```

#### 1.6 删除用户下的某个角色

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin user revoke-role coredns role01
```

#### 1.7. 删除用户

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin user delete coredns
```

### role相关命令

#### 2.1. 添加角色

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin role add role01 
```

#### 2.2. 查看所有角色

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin role list
```

#### 2.3. 给角色分配权限

##### 1、赋予访问权限

给 role01 角色赋予键 /foo 的读操作

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin role grant-permission role01 read /foo
```

 role01 角色赋予键 /foo/* 的写操作

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin role grant-permission role01 write /foo/*
```

 role01 角色赋予键 /foo 读写操作

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin role grant-permission role01 readwrite /foo/*
```

#####    2、收回访问权限

收回 role01 角色对 /foo 的权限

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin role revoke-permission role01 /foo
```

收回 role01 角色对 /foo/* 的权限

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin role revoke-permission role01 /foo/*
```

####  2.4. 查看角色所拥有的权限

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} \
--user root:admin role get role01
```

## 3、auth相关操作

开启auth

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} --user root:admin auth enable
```

关闭auth

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints ${ENDPOINTS} --user root:admin auth disable
```

## 4、写入数据与查看数据

写入

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
--user root:admin put /foo/test wzxmt
```

查看数据

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
--user root:admin get /foo/test
```

## 5、etcd集群节点添加与删除

#### 添加节点

添加第二个节点

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

更新/usr/lib/systemd/system/etcd.service的配置

```bash
--initial-cluster etcd-m1=https://10.0.0.31:2380,etcd-m2=https://10.0.0.32:2380
--initial-cluster-state=existing 
```

启动第二个节点

```bash
rm -rf /data/etcd/data
systemctl daemon-reload && systemctl start etcd
```

添加第三个节点

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

启动第三个节点

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

#### 删除节点

查看集群节点信息

```bash
etcdctl member list --write-out=table
```

删除节点

```bash
etcdctl member remove f1ec1f6015c9d4a4
```

## 二、持久化数据备份和恢复

etcd v2 和 v3 的数据不能混合存放。etcd的数据默认会存放在我们的命令工作目录中，我们发现数据所在的目录，会被分为两个文件夹中：

- snap: 存放快照数据,etcd防止WAL文件过多而设置的快照，存储etcd数据状态。
- wal: 存放预写式日志,最大的作用是记录了整个数据变化的全部历程。在etcd中，所有数据的修改在提交前，都要先写入到WAL中。

##  API 2 备份与恢复方法

### 1 模拟写入数据

```bash
写入数据
ETCDCTL_API=2 etcdctl \
--ca-file ${ETCD_SSL}/ca.pem \
--cert-file ${ETCD_SSL}/etcd.pem \
--key-file ${ETCD_SSL}/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
set /test wzxmt
读取API 2写入数据
ETCDCTL_API=2 etcdctl \
--ca-file ${ETCD_SSL}/ca.pem \
--cert-file ${ETCD_SSL}/etcd.pem \
--key-file ${ETCD_SSL}/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
get /test
```

### 2 备份

```bash
ETCDCTL_API=2 etcdctl backup --data-dir /data/etcd/data/ -backup-dir etcd_backup
tar -zcvf backup.etcd.tar.gz etcd_backup
```

### 3 恢复

将backup.etcd.tar.gz 复制到要恢复的集群任意一个服务器上

更新/usr/lib/systemd/system/etcd.service的配置

```bash
--initial-cluster etcd-m1=https://10.0.0.31:2380
--initial-cluster-state=new 
```

修改数据

```bash
tar -xvf backup.etcd.tar.gz
rm -rf /data/etcd/data
mv etcd_backup /data/etcd/data
```

强制拉起一个etcd， 数据加载成功后，关闭当前节点。

```bash
etcd -data-dir=/data/etcd/data --name=etcd-m1 --force-new-cluster
```

启动第一个节点

```bash
systemctl daemon-reload && systemctl start etcd.service 
```

查看数据

```bash
ETCDCTL_API=2 etcdctl \
--ca-file ${ETCD_SSL}/ca.pem \
--cert-file ${ETCD_SSL}/etcd.pem \
--key-file ${ETCD_SSL}/etcd-key.pem \
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

### 4 验证数据完整性

```bash
ETCDCTL_API=2 etcdctl \
--ca-file ${ETCD_SSL}/ca.pem \
--cert-file ${ETCD_SSL}/etcd.pem \
--key-file ${ETCD_SSL}/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
get /test
```

做好数据验证，如没问题，将所有节点的ETCD_INITIAL_CLUSTER更新为3个节点的，然后重启。

## API 3 备份与恢复方法

### 1 模拟写入数据

使用API 3写入数据库

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
put /name/1 test
```

读取数据

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
get  /name/1
```

### 2 备份etcd数据

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
snapshot save mysnapshot.db
```

### 3 停止etcd集群

查看状态

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
endpoint status
```

停止etcd服务

```bash
systemctl stop etcd
```

删除etcd数据

```bash
rm -rf /data/etcd/data
```

### 4 使用备份数据进行恢复

恢复10.0.0.31节点数据

```bash
etcdctl  snapshot restore mysnapshot.db \
--name=etcd01 \
--data-dir=/data/etcd/data \
--initial-advertise-peer-urls=https://10.0.0.31:2380 \
--initial-cluster etcd01=https://10.0.0.31:2380,etcd02=https://10.0.0.32:2380,etcd03=https://10.0.0.33:2380 \
--initial-cluster-token=etcd-cluster
```

恢复10.0.0.32节点数据

```bash
etcdctl  snapshot restore mysnapshot.db \
--name=etcd02 \
--data-dir=/data/etcd/data \
--initial-advertise-peer-urls=https://10.0.0.32:2380 \
--initial-cluster etcd01=https://10.0.0.31:2380,etcd02=https://10.0.0.32:2380,etcd03=https://10.0.0.33:2380 \
--initial-cluster-token=etcd-cluster
```

恢复10.0.0.33节点数据

```bash
etcdctl  snapshot restore mysnapshot.db \
--name=etcd03 \
--data-dir=/data/etcd/data \
--initial-advertise-peer-urls=https://10.0.0.33:2380 \
--initial-cluster etcd01=https://10.0.0.31:2380,etcd02=https://10.0.0.32:2380,etcd03=https://10.0.0.33:2380 \
--initial-cluster-token=etcd-cluster
```

### 5 启动Etcd服务

分别在etcd所在主机执行如下命令：

```bash
systemctl start etcd
```

### 6 查看状态

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
endpoint status --write-out=table
```

### 7 验证数据完整性

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
get  /name/1
```

## 备份脚本

v2

```bash
mkdir -p /usr/local/scripts
cat << 'EOF' >/usr/local/scripts/etcd-backup-v2.sh
#!/bin/bash
timestamp=`date +%Y%m%d-%H%M%S`
data_dir=/data/etcd/data
back_dir=/data/backup/etcd
cluster_name=test

mkdir -p ${back_dir} && cd ${back_dir}
ETCDCTL_API=2 /usr/local/bin/etcdctl backup --data-dir ${data_dir} -backup-dir ${back_dir}/etcd-${timestamp}
tar zcvf ${cluster_name}_snapshot_${timestamp}.tar.gz etcd-${timestamp} --remove-files
EOF
chmod +x /usr/local/scripts/*
echo -e "\n#etcd backup \n0 0 * * * /usr/local/scripts/etcd-backup-v2.sh" >>/var/spool/cron/root
```

v3

```bash
mkdir -p /usr/local/scripts
cat << 'EOF' >/usr/local/scripts/etcd-backup-v3.sh
#!/bin/bash
timestamp=`date +%Y%m%d-%H%M%S`
back_dir=/data/backup/etcd
etcd_ip=10.0.0.31
ssl_dir=${ETCD_SSL}
cluster_name=test
file_name=${back_dir}/${cluster_name}_snapshot_$timestamp.db

mkdir -p $back_dir
ETCDCTL_API=3 /usr/local/bin/etcdctl \
--endpoints="https://${etcd_ip}:2379" \
--cert=${ssl_dir}/etcd.pem \
--key=${ssl_dir}/etcd-key.pem \
--cacert=${ssl_dir}/ca.pem \
snapshot save ${file_name}
gzip ${file_name}
EOF
chmod +x /usr/local/scripts/*
echo -e "\n#etcd backup \n0 0 * * * /usr/local/scripts/etcd-backup-v3.sh" >>/var/spool/cron/root
```

#  三、ETCD常见问题

由于ETCD集群需要选举产生leader，所以集群节点数目需要为奇数来保证正常进行选举。而集群节点的数量并不是越多越好，过多的节点会导致集群同步的时间变长，使得leader写入的效率降低。我们线上的ETCD集群由三个节点组成(即宕机一台，集群可正常工作)，并开启了认证。以下是日常运维工作中，遇到问题的处理过程。

## 1、集群一个节点宕机的恢复步骤

一个节点宕机，并不会影响整个集群的正常工作。此时可通过以下几步恢复集群：

### 1）在正常节点上查看集群状态并摘除异常节点

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} endpoint status --write-out=table
```

### 2）摘除异常节点

```bash
etcdctl member remove f1ec1f6015c9d4a4
```

### 3）重新部署服务后，将节点重新加入集群

- 由于ETCD集群证书依赖于服务器IP，为避免重新制作证书，需要保持节点IP不变。在部署好节点上服务后，先不要启动。

- 删除新增成员的旧数据目录，更改相关配置需将原etcd服务的旧数据目录删除，否则etcd会无法正常启动。将节点重新加入集群（name要与配置文件的--name一致）

  ```bash
  etcdctl --cacert=${ETCD_SSL}/ca.pem \
  --cert=${ETCD_SSL}/etcd.pem \
  --key=${ETCD_SSL}/etcd-key.pem \
  --endpoints=${ENDPOINTS} \
  member add etcd03 --peer-urls=https://10.0.0.33:2380
  ```

  此时查看集群状态，新加入的节点状态为unstarted

- 新增节点是加入已有集群，所以需要修改配置

  ```bash
  --initial-cluster-state=existing
  ```

- 启动服务 检测集群是否正常

  ```bash
  systemctl daemon-reload
  systemctl restart etcd.service
  ```

查看集群状态，若三台都正常，集群恢复。

## 2、集群超过半数节点宕机的恢复步骤

此时集群处于无法正常工作的状态，需要尽快恢复。若机器宕机重启，IP保持不变，则证书无需重新生成；若IP更换，则还需重新生成证书。集群恢复需要使用ETCD的备份数据(使用etcdctl snapshot save命令备份)，或者从ETCD数据目录复制snap/db文件。以下是恢复步骤：

### 1）将备份数据恢复至集群

- 集群部署完成后，先不启动ETCD服务，并将原有ETCD数据目录删除依次在三台节点上执行恢复数据的命令

  ```bash
  etcdctl  snapshot restore mysnapshot.db \
  --name=etcd01 \
  --data-dir=/data/etcd/data \
  --initial-advertise-peer-urls=https://10.0.0.31:2380 \
  --initial-cluster etcd01=https://10.0.0.31:2380,etcd02=https://10.0.0.32:2380,etcd03=https://10.0.0.33:2380 \
  --initial-cluster-token=etcd-cluster
  ```

### 2）启动ETCD服务，检查集群状态

```bash
systemctl start etcd
```

## 3、 database space exceeded报错恢复步骤

从报错的字面意思来看，是超出数据库空间导致。查看集群此时各节点的状态，发现DB SIZE为2.1GB。ETCD官方文档说明(https://etcd.io/docs/v3.3.12/dev-guide/limit/)提到ETCD默认的存储大小是2GB。超出后，集群无法进行写入。以下为恢复步骤：

### 1）备份数据

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
snapshot save mysnapshot.db
```

### 2）获取reversion

```bash
etcdctl --write-out="json" --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
endpoint status |grep -o '"revision":[0-9]*'
```

### 3）compact(压缩旧版本)

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
compact $revision
```

### 4）defrag(清理磁盘碎片)

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
defrag
```

### 5）删除清除(必需删除，否则集群仍然无法使用)

```bash
etcdctl --write-out="json" --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} \
alarm disarm
```

以上就是对ETCD集群日常维护的总结，为了使服务更加稳定的运行，建议定时备份和压缩数据，并增加集群监控(与Prometheus配合使用)。

## 4、etcd强制删除数据

有时候通过以下删除数据时删除不掉，可能是之前删除顺序有问题，没有删干净pod，就删除命名空间，导致删除不掉.

```bash
# 删除POD
kubectl delete pod PODNAME --force --grace-period=0
# 删除NAMESPACE
kubectl delete namespace NAMESPACENAME --force --grace-period=0
```

**直接从ETCD中删除源数据**

```bash
# 删除default namespace下的pod名为pod-to-be-deleted-0
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
del /registry/pods/default/pod-to-be-deleted-0
# 删除需要删除的NAMESPACE
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
del /registry/namespaces/NAMESPACENAME
```

**查询都有哪些namespaces**

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
get /registry/namespaces/ --prefix --keys-only

/registry/namespaces/default
/registry/namespaces/ingress-system
/registry/namespaces/kube-node-lease
/registry/namespaces/kube-public
/registry/namespaces/kube-system
/registry/namespaces/test
```

**与kubectl查看的结果一致**

```bash
[root@supper ~]# kubectl get ns
NAME                   STATUS        AGE
default                Active        28d
ingress-system         Active        28d
kube-node-lease        Active        28d
kube-public            Active        28d
kube-system            Active        28d
test                   Active        4h51m
```

**在查询default namespace中的pod**

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
get /registry/pods/default --prefix --keys-only

/registry/pods/default/myapp-deploy-c7b5fb585-2zppw
/registry/pods/default/myapp-deploy-c7b5fb585-p4m66
/registry/pods/default/myapp-deploy-c7b5fb585-pb296
```

**kubectl命令看到结果与etcd中一致**

```bash
[root@supper ~]# kubectl get pods
NAME                           READY   STATUS    RESTARTS   AGE
myapp-deploy-c7b5fb585-2zppw   1/1     Running   0          6m26s
myapp-deploy-c7b5fb585-p4m66   1/1     Running   0          8m11s
myapp-deploy-c7b5fb585-pb296   1/1     Running   0          8m11s
```

**在etcd中删除pod testpod-t7ps7**

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints="https://10.0.0.31:2379" \
del /registry/pods/default/myapp-deploy-c7b5fb585-pb296    

1
```

**再次查看pod，发现pod已经没有了**

```bash
[root@supper ~]# kubectl get pods
NAME                           READY   STATUS    RESTARTS   AGE
myapp-deploy-c7b5fb585-2zppw   1/1     Running   0          7m55s
myapp-deploy-c7b5fb585-8gmff   1/1     Running   0          12s
myapp-deploy-c7b5fb585-p4m66   1/1     Running   0          9m40s
```

## 5、重置ETCD集群

先通过 `--force-new-cluster` 强行拉起一个 etcd 集群，抹除了原有 data-dir 中原有集群的属性信息（内部猜测），然后通过加入新成员的方式扩展集群到指定的数目。
