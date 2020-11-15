# [部署Kubernetesv 1.18高可用集群](https://www.cnblogs.com/lizhenliang/p/13025158.html)



## 一、前置知识点

### 1.1 生产环境可部署Kubernetes集群的两种方式

目前生产部署Kubernetes集群主要有两种方式：

- **kubeadm**

Kubeadm是一个K8s部署工具，提供kubeadm init和kubeadm join，用于快速部署Kubernetes集群。

官方地址：https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm/

- **二进制包**

从github下载发行版的二进制包，手动部署每个组件，组成Kubernetes集群。

Kubeadm降低部署门槛，但屏蔽了很多细节，遇到问题很难排查。如果想更容易可控，推荐使用二进制包部署Kubernetes集群，虽然手动部署麻烦点，期间可以学习很多工作原理，也利于后期维护。

### 1.2 安装要求

在开始之前，部署Kubernetes集群机器需要满足以下几个条件：

- 一台或多台机器，操作系统 CentOS7.x-86_x64
- 硬件配置：2GB或更多RAM，2个CPU或更多CPU，硬盘30GB或更多
- 可以访问外网，需要拉取镜像，如果服务器不能上网，需要提前下载镜像并导入节点
- 禁止swap分区

### 1.3 准备环境

软件环境：

| **软件**   | **版本**               |
| ---------- | ---------------------- |
| 操作系统   | CentOS7.8_x64 （mini） |
| Docker     | 19-ce                  |
| Kubernetes | 1.18                   |

服务器整体规划：

| **角色** | **IP**     | **组件**                                                     |
| -------- | ---------- | ------------------------------------------------------------ |
| m1       | 10.0.0.31  | kube-apiserver，kube-controller-manager，kube-scheduler，etcd，Nginx L4，keepalived |
| m2       | 10.0.0.32  | kube-apiserver，kube-controller-manager，kube-scheduler，etcd，Nginx L4，keepalived |
| m3       | 10.0.0.33  | kube-apiserver，kube-controller-manager，kube-scheduler，etcd，Nginx L4，keepalived |
| n1       | 10.0.0.41  | kubelet，kube-proxy，docker                                  |
| n2       | 10.0.0.42  | kubelet，kube-proxy，docker                                  |
| VIP      | 10.0.0.100 |                                                              |

### 1.4 多Master架构图：

![kubernetes](https://k8s-1252881505.cos.ap-beijing.myqcloud.com/k8s-1/multi-master.jpg)

### 1.5 操作系统初始化配置

```shell
# 关闭防火墙
systemctl stop firewalld
systemctl disable firewalld

# 关闭selinux
sed -i 's/enforcing/disabled/' /etc/selinux/config  # 永久
setenforce 0  # 临时

# 关闭swap
swapoff -a  # 临时
sed -ri 's/.*swap.*/#&/' /etc/fstab    # 永久

# 根据规划设置主机名
hostnamectl set-hostname <hostname>

# 在master添加hosts
cat >> /etc/hosts << EOF
10.0.0.31 m1
10.0.0.32 m2
10.0.0.33 m3
10.0.0.41 n1
10.0.0.42 n2
EOF

# 内核参数优化
cat << EOF >/etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
net.ipv4.neigh.default.gc_thresh1=1024
net.ipv4.neigh.default.gc_thresh1=2048
net.ipv4.neigh.default.gc_thresh1=4096
vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF

#加载内核
sysctl -p /etc/sysctl.d/kubernetes.conf

# 时间同步
yum install ntpdate -y
ntpdate time.windows.com

#kube-proxy开启ipvs的前提需要加载以下的内核模块：
cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
EOF

#加载内核模块
chmod 755 /etc/sysconfig/modules/ipvs.modules
bash /etc/sysconfig/modules/ipvs.modules
lsmod|egrep "ip_vs|nf_conntrack_ipv4"

#各节点安装了ipset软件包与管理工具
yum install -y ipset ipvsadm

升级系统内核为 4.44
CentOS 7.x 系统自带的 3.10.x 内核存在一些 Bugs，导致运行的 Docker、Kubernetes 不稳定
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm

安装完成后检查 /boot/grub2/grub.cfg 中对应内核 menuentry 中是否包含 initrd16 配置，如果没有，再安装一次！
yum --enablerepo=elrepo-kernel install -y kernel-lt
设置开机从新内核启动
grub2-set-default 0
查看内核
uname -r
4.4.218-1.el7.elrepo.x86_64
```

### 1.6 集群网络规划

|  网络名称  |     网段      |
| :--------: | :-----------: |
|  Node ip   |  10.0.0.0/24  |
| Service ip | 10.96.0.0/24  |
|   Pod ip   | 172.16.0.0/16 |
|    Dns     |  10.96.0.10   |

## 二、部署Etcd集群

Etcd 是一个分布式键值存储系统，Kubernetes使用Etcd进行数据存储，所以先准备一个Etcd数据库，为解决Etcd单点故障，应采用集群方式部署，这里使用3台组建集群，可容忍1台机器故障，当然，你也可以使用5台组建集群，可容忍2台机器故障。

| **节点名称** | **IP**    |
| ------------ | --------- |
| etcd-1       | 10.0.0.31 |
| etcd-2       | 10.0.0.32 |
| etcd-3       | 10.0.0.33 |

### 2.1 准备cfssl证书生成工具

cfssl是一个开源的证书管理工具，使用json文件生成证书，相比openssl更方便使用。

找任意一台服务器操作，这里用m1节点。

```shell
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -O /usr/local/bin/cfssl
wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -O /usr/local/bin/cfssljson
chmod +x /usr/local/bin/cfssl*
```

### 2.2 生成证书

#### 1. 自签证书颁发机构（CA）

创建工作目录：

```shell
mkdir /etc/kubernetes/pki -p && cd /etc/kubernetes/pki
```

自签CA：

```shell
cat >ca-config.json << EOF
{"signing":{"default":{"expiry":"87600h"},"profiles":{"kubernetes":{"usages":["signing","key encipherment","server auth","client auth"],"expiry":"87600h"}}}}
EOF

cat > ca-csr.json << EOF 
{"CN": "kubernetes","key": {"algo": "rsa","size": 2048},"names":[{"C": "CN","ST": "BeiJing","L": "BeiJing","O": "kubernetes","OU": "k8s"}]}
EOF
```

生成集群 CA证书：

```shell
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
```

#### 2.生成ETCD证书

```shell
cat > etcd-csr.json <<EOF 
{"CN":"etcd","key":{"algo":"rsa","size":2048},"names":[{"C":"CN","ST":"BeiJing","L":"BeiJing","O":"etcd","OU":"etcd"}]}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -hostname=127.0.0.1,10.0.0.31,10.0.0.32,10.0.0.33 -profile=kubernetes etcd-csr.json|cfssljson -bare etcd
```

#### 3.生成server 证书

```shell
cat > server-csr.json <<EOF 
{"CN":"server","key":{"algo":"rsa","size":2048},"names":[{"C":"CN","ST":"BeiJing","L":"BeiJing","O":"kubernetes","OU":"k8s"}]}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -hostname=10.96.0.1,10.0.0.1,172.16.0.1,127.0.0.1,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.default.svc.cluster.local,10.0.0.31,10.0.0.32,10.0.0.33,10.0.0.100 -profile=kubernetes server-csr.json|cfssljson -bare server
```

#### 4.生成kube-proxy证书

```shell
cat > kube-proxy-csr.json << EOF
{"CN":"system:kube-proxy","key":{"algo": "rsa","size":2048},"names":[{"C":"CN","L":"BeiJing","ST":"BeiJing","O":"kubernetes","OU":"k8s"}]}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy
```

#### 5.生成front-proxy-client证书

```
cat >front-proxy-client-csr.json<<EOF
{"CN":"front-proxy-client","key":{"algo":"rsa","size":2048},"names":[{"C":"CN","ST":"BeiJing","L":"BeiJing","O":"system:masters","OU":"k8s"}]}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes front-proxy-client-csr.json | cfssljson -bare front-proxy-client
```

#### 6. 生成admin私钥和证书

```
cat > admin-csr.json <<EOF 
{"CN":"admin","key":{"algo":"rsa","size":2048},"names":[{"C":"CN","ST":"BeiJing","L":"BeiJing","O":"system:masters","OU":"k8s"}]}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json|cfssljson -bare admin
```

删除证书请求文件

```
rm -f *csr *csr.json
```

### 2.3 从Github下载二进制文件

下载地址：https://github.com/etcd-io/etcd/releases/download/v3.4.9/etcd-v3.4.9-linux-amd64.tar.gz

### 2.4 部署Etcd集群

以下在节点1上操作，为简化操作，待会将节点1生成的所有文件拷贝到节点2和节点3.

#### 1. 创建工作目录并解压二进制包

```shell
tar zxvf etcd-v3.4.9-linux-amd64.tar.gz
for n in m{1..3};do rsync -av etcd-v3.4.9-linux-amd64/{etcd,etcdctl} $n:/usr/local/bin/;done
```

#### 2. systemd管理etcd

```shell
cat << 'EOF' >/usr/lib/systemd/system/etcd.service 
[Unit]
Description=Etcd Server
After=neCNork.target
After=network-online.target
Wants=network-online.target
[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \
--name=etcd01 \
--logger=zap \
--enable-v2=true \
--data-dir=/data/etcd \
--listen-peer-urls=https://10.0.0.31:2380 \
--listen-client-urls=https://10.0.0.31:2379,http://127.0.0.1:2379 \
--advertise-client-urls=https://10.0.0.31:2379 \
--initial-advertise-peer-urls=https://10.0.0.31:2380 \
--initial-cluster etcd01=https://10.0.0.31:2380,etcd02=https://10.0.0.32:2380,etcd03=https://10.0.0.33:2380 \
--initial-cluster-token=etcd-cluster \
--initial-cluster-state=new \
--cert-file=/etc/kubernetes/pki/etcd.pem \
--key-file=/etc/kubernetes/pki/etcd-key.pem \
--peer-cert-file=/etc/kubernetes/pki/etcd.pem \
--peer-key-file=/etc/kubernetes/pki/etcd-key.pem \
--trusted-ca-file=/etc/kubernetes/pki/ca.pem \
--peer-trusted-ca-file=/etc/kubernetes/pki/ca.pem \
--auto-compaction-mode=periodic \
--auto-compaction-retention=1 \
--max-request-bytes=33554432 \
--quota-backend-bytes=6442450944 \
--heartbeat-interval=250 \
--election-timeout=2000
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
```

启动并设置开机启动

```shell
systemctl daemon-reload
systemctl enable --now etcd
```

#### 3. 将上面节点1所有生成的文件拷贝到节点2和节点3

```shell
for n in m{1..3};do rsync -av /etc/kubernetes/pki $n:/etc/kubernetes/;done
for n in m{1..3};do rsync -av /usr/lib/systemd/system/etcd.service $n:/usr/lib/systemd/system/;done
```

然后在节点2和节点3分别修改etcd.conf配置文件中的节点名称和当前服务器IP：

最后启动etcd并设置开机启动，同上。

#### 4. 查看集群状态

```shell
etcdctl --cacert=/etc/kubernetes/pki/ca.pem \
--cert=/etc/kubernetes/pki/etcd.pem \
--key=/etc/kubernetes/pki/etcd-key.pem \
--endpoints="https://10.0.0.31:2379,https://10.0.0.32:2379,https://10.0.0.33:2379" endpoint health

https://10.0.0.31:2379 is healthy: successfully committed proposal: took = 10.737332ms
https://10.0.0.32:2379 is healthy: successfully committed proposal: took = 11.069201ms
https://10.0.0.33:2379 is healthy: successfully committed proposal: took = 11.845976ms
```

如果输出上面信息，就说明集群部署成功。如果有问题第一步先看日志：/var/log/message 或 journalctl -u etcd

## 四、部署Master Node

### 4.1 从Github下载二进制文件

下载地址： https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.18.md#v1183

> 注：打开链接你会发现里面有很多包，下载一个server包就够了，包含了Master和Worker Node二进制文件。

Master创建文件

```shell
mkdir -p /etc/kubernetes/pki ${HOME}/.kube /data/kubernetes/logs/{kube-scheduler,kube-apiserver,kube-controller-manager}
```

### 4.2 解压二进制包

```shell
tar zxvf kubernetes-server-linux-amd64.tar
cd kubernetes/server/bin
for n in m{1..3};do rsync -av kube-apiserver kube-scheduler kube-controller-manager kubectl $n:/usr/local/bin/;done
```

### 4.3 部署kube-apiserver

#### 1. 创建审计策略

```shell
cat << 'EOF' >/etc/kubernetes/pki/audit.yaml
apiVersion: audit.k8s.io/v1beta1 # This is required.
kind: Policy
# Don't generate audit events for all requests in RequestReceived stage.
omitStages:
  - "RequestReceived"
rules:
  # Log pod changes at RequestResponse level
  - level: RequestResponse
    resources:
    - group: ""
      # Resource "pods" doesn't match requests to any subresource of pods,
      # which is consistent with the RBAC policy.
      resources: ["pods"]
  # Log "pods/log", "pods/status" at Metadata level
  - level: Metadata
    resources:
    - group: ""
      resources: ["pods/log", "pods/status"]
  # Don't log requests to a configmap called "controller-leader"
  - level: None
    resources:
    - group: ""
      resources: ["configmaps"]
      resourceNames: ["controller-leader"]
  # Don't log watch requests by the "system:kube-proxy" on endpoints or services
  - level: None
    users: ["system:kube-proxy"]
    verbs: ["watch"]
    resources:
    - group: "" # core API group
      resources: ["endpoints", "services"]
  # Don't log authenticated requests to certain non-resource URL paths.
  - level: None
    userGroups: ["system:authenticated"]
    nonResourceURLs:
    - "/api*" # Wildcard matching.
    - "/version"
  # Log the request body of configmap changes in kube-system.
  - level: Request
    resources:
    - group: "" # core API group
      resources: ["configmaps"]
    # This rule only applies to resources in the "kube-system" namespace.
    # The empty string "" can be used to select non-namespaced resources.
    namespaces: ["kube-system"]
  # Log configmap and secret changes in all other namespaces at the Metadata level.
  - level: Metadata
    resources:
    - group: "" # core API group
      resources: ["secrets", "configmaps"]
  # Log all other resources in core and extensions at the Request level.
  - level: Request
    resources:
    - group: "" # core API group
    - group: "extensions" # Version of group should NOT be included.
  # A catch-all rule to log all other requests at the Metadata level.
  - level: Metadata
    # Long-running requests like watches that fall under this rule will not
    # generate an audit event in RequestReceived.
    omitStages:
      - "RequestReceived"
EOF
```

#### 2. systemd管理apiserver

```shell
cat << 'EOF' >/usr/lib/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
  --audit-log-maxage=30 \
  --audit-log-maxbackup=10 \
  --audit-log-maxsize=100 \
  --service-node-port-range=30000-32767 \
  --audit-policy-file /etc/kubernetes/pki/audit.yaml \
  --audit-log-path /data/kubernetes/logs/kube-apiserver/audit-log \
  --allow-privileged=true \
  --authorization-mode=Node,RBAC \
  --client-ca-file=/etc/kubernetes/pki/ca.pem \
  --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,NodeRestriction \
  --enable-bootstrap-token-auth=true \
  --etcd-cafile=/etc/kubernetes/pki/ca.pem \
  --etcd-certfile=/etc/kubernetes/pki/etcd.pem \
  --etcd-keyfile=/etc/kubernetes/pki/etcd-key.pem \
  --etcd-servers=https://10.0.0.31:2379,https://10.0.0.32:2379,https://10.0.0.33:2379 \
  --kubelet-certificate-authority=/etc/kubernetes/pki/ca.pem \
  --kubelet-client-certificate=/etc/kubernetes/pki/server.pem \
  --kubelet-client-key=/etc/kubernetes/pki/server-key.pem \
  --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname \
  --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.pem \
  --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client-key.pem \
  --requestheader-allowed-names="aggregstor" \
  --requestheader-client-ca-file=/etc/kubernetes/pki/ca.pem \
  --requestheader-extra-headers-prefix=X-Remote-Extra- \
  --requestheader-group-headers=X-Remote-Group \
  --requestheader-username-headers=X-Remote-User \
  --enable-aggregator-routing=true \
  --secure-port=6443 \
  --service-account-key-file=/etc/kubernetes/pki/sa.pub \
  --service-cluster-ip-range 10.96.0.0/16 \
  --tls-cert-file /etc/kubernetes/pki/server.pem \
  --tls-private-key-file /etc/kubernetes/pki/server-key.pem \
  --log-dir  /data/kubernetes/logs/kube-apiserver \
  --alsologtostderr=true \
  --logtostderr=false \
  --v=2 
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
```

#### 3. Service Account Key,api与pod间的认证

```bash
cd /etc/kubernetes/pki
openssl genrsa -out sa.key 2048
openssl rsa -in sa.key -pubout -out sa.pub
```

分发配置文件

```bash
for n in m{1..3};do rsync -av /etc/kubernetes/pki $n:/etc/kubernetes/;done
for n in m{1..3};do rsync -av /usr/lib/systemd/system/kube-apiserver.service $n:/usr/lib/systemd/system/;done
```

启动并设置开机启动

```shell
for n in m{1..3};do ssh $n "systemctl daemon-reload";done 
for n in m{1..3};do ssh $n "systemctl enable --now kube-apiserver";done
```

### 4.4 部署kube-controller-manager

systemd管理controller-manager

```shell
cat << 'EOF' >/usr/lib/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \
  --master=127.0.0.1:8080 \
  --secure-port=10252 \
  --bind-address=127.0.0.1 \
  --allocate-node-cidrs=true \
  --client-ca-file=/etc/kubernetes/pki/ca.pem \
  --cluster-cidr=172.16.0.0/16 \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/etc/kubernetes/pki/ca.pem \
  --cluster-signing-key-file=/etc/kubernetes/pki/ca-key.pem \
  --controllers=*,bootstrapsigner,tokencleaner \
  --leader-elect=true \
  --node-cidr-mask-size=24 \
  --requestheader-allowed-names="aggregstor" \
  --requestheader-client-ca-file=/etc/kubernetes/pki/ca.pem \
  --requestheader-extra-headers-prefix=X-Remote-Extra- \
  --requestheader-group-headers=X-Remote-Group \
  --requestheader-username-headers=X-Remote-User \
  --root-ca-file=/etc/kubernetes/pki/ca.pem \
  --service-account-private-key-file=/etc/kubernetes/pki/sa.key \
  --use-service-account-credentials=true \
  --horizontal-pod-autoscaler-use-rest-clients=true \
  --feature-gates=RotateKubeletServerCertificate=true \
  --log-dir /data/kubernetes/logs/kube-controller-manager \
  --alsologtostderr=true \
  --logtostderr=false \
  --v=2 \
  --horizontal-pod-autoscaler-sync-period=10s \
  --concurrent-deployment-syncs=10 \
  --concurrent-gc-syncs=30 \
  --node-cidr-mask-size=24 \
  --pod-eviction-timeout=6m \
  --terminated-pod-gc-threshold=10000 \
  --experimental-cluster-signing-duration=87600h0m0s
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
```

启动并设置开机启动

```shell
for n in m{1..3};do rsync -av /usr/lib/systemd/system/kube-controller-manager.service $n:/usr/lib/systemd/system/;done
for n in m{1..3};do ssh $n "systemctl daemon-reload";done 
for n in m{1..3};do ssh $n "systemctl enable --now kube-controller-manager";done
```

查看leader信息

```
kubectl get ep kube-controller-manager -n kube-system -o yaml
```

### 4.5 部署kube-scheduler

 systemd管理scheduler

```shell
cat << 'EOF' >/usr/lib/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \
  --leader-elect=true \
  --alsologtostderr=true \
  --master=127.0.0.1:8080 \
  --secure-port=10259 \
  --bind-address=127.0.0.1 \
  --client-ca-file=/etc/kubernetes/pki/ca.pem \
  --requestheader-allowed-names="aggregstor" \
  --requestheader-client-ca-file=/etc/kubernetes/pki/ca.pem \
  --requestheader-extra-headers-prefix="X-Remote-Extra-" \
  --requestheader-group-headers=X-Remote-Group \
  --requestheader-username-headers=X-Remote-User \
  --v=2 \
  --logtostderr=false \
  --log-dir=/data/kubernetes/logs/kube-scheduler \
RestartSec=10s
LimitNOFILE=65535
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
```

启动并设置开机启动

```shell
for n in m{1..3};do rsync -av /usr/lib/systemd/system/kube-scheduler.service $n:/usr/lib/systemd/system/;done
for n in m{1..3};do ssh $n "systemctl daemon-reload";done 
for n in m{1..3};do ssh $n "systemctl enable --now kube-scheduler";done
```

查看leader信息

```
kubectl get ep kube-scheduler -n kube-system -o yaml
```

在其他master上以同样的方式部署kube-apiserver，kube-controller-manager与kube-scheduler

### 4.6 启用 TLS Bootstrapping 机制

TLS Bootstraping：Master apiserver启用TLS认证后，Node节点kubelet和kube-proxy要与kube-apiserver进行通信，必须使用CA签发的有效证书才可以，当Node节点很多时，这种客户端证书颁发需要大量工作，同样也会增加集群扩展复杂度。为了简化流程，Kubernetes引入了TLS bootstraping机制来自动颁发客户端证书，kubelet会以一个低权限用户自动向apiserver申请证书，kubelet的证书由apiserver动态签署。所以强烈建议在Node上使用这种方式，目前主要用于kubelet，kube-proxy还是由我们统一颁发一个证书。

TLS bootstraping 工作流程：

![img](https://k8s-1252881505.cos.ap-beijing.myqcloud.com/k8s-1/bootstrap-token.png)

##### 1 生成Token

```bash
KUBE_APISERVER="https://10.0.0.100:8443"
TOKEN_ID=$(openssl rand -hex 3)
TOKEN_SECRET=$(openssl rand -hex 8)
BOOTSTRAP_TOKEN="${TOKEN_ID}.${TOKEN_SECRET}"
AUTH_EXTRA_GROUPS="system:bootstrappers:default-node-token"
```

##### 2 建立TLS bootstrap secret来提供自动签证使用

```bash
cat << EOF >bootstrap-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-token-${TOKEN_ID}
  namespace: kube-system
type: bootstrap.kubernetes.io/token
stringData:
  description: "The bootstrap token for k8s."
  token-id: ${TOKEN_ID}
  token-secret: ${TOKEN_SECRET}
  expiration: 2029-07-16T00:00:00Z
  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"
  auth-extra-groups: ${AUTH_EXTRA_GROUPS}
EOF
kubectl apply -f  bootstrap-secret.yaml
```

##### 3 将自定义的auth-extra-groups绑定角色system:node-bootstrapper

```bash
kubectl create clusterrolebinding kubelet-bootstrap \
--clusterrole system:node-bootstrapper \
--group ${AUTH_EXTRA_GROUPS}
```

##### 4 将自定义的auth-extra-groups绑定角色,实现自动签署证书请求

```bash
kubectl create clusterrolebinding node-autoapprove-bootstrap \
--clusterrole system:certificates.k8s.io:certificatesigningrequests:nodeclient \
--group ${AUTH_EXTRA_GROUPS}
```

##### 5 将system:node绑定角色,实现自动刷新node节点过期证书

```bash
kubectl create clusterrolebinding node-autoapprove-certificate-rotation \
--clusterrole system:certificates.k8s.io:certificatesigningrequests:selfnodeclient \
--group system:node
```

#### 6 授权匿名用户访问

```bash
kubectl create clusterrolebinding test:anonymous --clusterrole=cluster-admin --user=system:anonymous
```

### 4.7 生成kubeconfig

```shell
KUBE_APISERVER="https://10.0.0.100:8443"
K8S_DIR=/etc/kubernetes
cd $K8S_DIR/pki
```

**kubelet bootstrapping kubeconfig**

```shell
kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=${KUBE_APISERVER} --kubeconfig=${K8S_DIR}/bootstrap-kubelet.kubeconfig

kubectl config set-credentials tls-bootstrap-token-user --token=${BOOTSTRAP_TOKEN} --kubeconfig=${K8S_DIR}/bootstrap-kubelet.kubeconfig

kubectl config set-context default --cluster=kubernetes --user=tls-bootstrap-token-user --kubeconfig=${K8S_DIR}/bootstrap-kubelet.kubeconfig

kubectl config use-context default --kubeconfig=${K8S_DIR}/bootstrap-kubelet.kubeconfig
```

**kube-proxy kubeconfig**

```shell
kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=${KUBE_APISERVER} --kubeconfig=${K8S_DIR}/kube-proxy.kubeconfig

kubectl config set-credentials kube-proxy --client-certificate=kube-proxy.pem --client-key=kube-proxy-key.pem --embed-certs=true --kubeconfig=${K8S_DIR}/kube-proxy.kubeconfig

kubectl config set-context default --cluster=kubernetes --user=kube-proxy --kubeconfig=${K8S_DIR}/kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=${K8S_DIR}/kube-proxy.kubeconfig
```

**admin kubeconfig**

```shell
kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=${KUBE_APISERVER} --kubeconfig=${K8S_DIR}/admin.kubeconfig

kubectl config set-credentials admin --client-certificate=admin.pem --client-key=admin-key.pem --embed-certs=true --kubeconfig=${K8S_DIR}/admin.kubeconfig

kubectl config set-context admin@kubernetes --cluster=kubernetes --user=admin --kubeconfig=${K8S_DIR}/admin.kubeconfig

kubectl config use-context admin@kubernetes --kubeconfig=${K8S_DIR}/admin.kubeconfig
```

配置默认kubectl文件

```shell
for n in m{1..3};do rsync -av /etc/kubernetes $n:/etc/;done
for n in m{1..3};do rsync -av ${K8S_DIR}/admin.kubeconfig $n:/root/.kube/config;done
```

### 4.6 apiserver高可用

#### 1 各master节点安装haproxy keepalived

```shell
yum -y install haproxy keepalived
```

#### 2 修改配置文件

注意:keepalived配置文件，其余节点修改state为BACKUP，priority小于主节点即可；检查网卡名称并修改

```bash
cat<< EOF >/etc/keepalived/keepalived.conf
vrrp_script chk_apiserver {
        script "/etc/keepalived/check_apiserver.sh"
        interval 4
        weight 60  
}
vrrp_instance VI_1 {
    state MASTER  
    interface eth0
    virtual_router_id 51
    priority 150
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    track_script {
        chk_apiserver
    }
    virtual_ipaddress {
        10.0.0.100
    }
}
EOF
cat << 'EOF' >/etc/keepalived/check_apiserver.sh
#!/bin/bash
flag=$(ps -ef|grep -v grep|grep -w 'kube-apiserver' &>/dev/null;echo $?)
if [[ $flag != 0 ]];then
        echo "kube-apiserver is down,close the keepalived"
        systemctl stop keepalived
fi
EOF
cat > /etc/haproxy/haproxy.cfg << EOF 
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon
    stats socket /var/lib/haproxy/stats
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000
#---------------------------------------------------------------------
frontend  k8s-api 
   bind *:8443
   mode tcp
   default_backend             apiserver
#---------------------------------------------------------------------
backend apiserver
    balance     roundrobin
    mode tcp
    server  m1 10.0.0.31:6443 check weight 1 maxconn 2000 check inter 2000 rise 2 fall 3
    server  m2 10.0.0.32:6443 check weight 1 maxconn 2000 check inter 2000 rise 2 fall 3
    server  m3 10.0.0.33:6443 check weight 1 maxconn 2000 check inter 2000 rise 2 fall 3
EOF
```

#### 4 启动服务

```bash
chmod 644 /etc/keepalived/keepalived.conf && chmod +x /etc/keepalived/check_apiserver.sh && systemctl enable --now haproxy keepalived
#查看VIP是否工作正常
ping 10.0.0.100 -c 3
```

#### 5 查看apiserver集群健康状况

```bash
[root@m1 pki]# kubectl cluster-info
Kubernetes master is running at https://10.0.0.100:8443

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

#### 6 查看集群状态

所有组件都已经启动成功，通过kubectl工具查看当前集群组件状态：

```shell
kubectl get cs
NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok                  
controller-manager   Healthy   ok                  
etcd-2               Healthy   {"health":"true"}   
etcd-1               Healthy   {"health":"true"}   
etcd-0               Healthy   {"health":"true"}  
```

如上输出说明Master节点组件运行正常。

## 五、部署Worker Node

### 5.1 安装Docker

下载地址：https://download.docker.com/linux/static/stable/x86_64/docker-19.03.9.tgz

以下在node节点操作。这里采用二进制安装，用yum安装也一样。

### 5.2 解压二进制包

```shell
tar zxvf docker-19.03.9.tgz
mv docker/* /usr/bin
```

### 5.3 systemd管理docker

```shell
cat << 'EOF' >/usr/lib/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecStartPost=/sbin/iptables -I FORWARD -s 0.0.0.0/0 -j ACCEPT
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF
```

### 3.3 创建配置文件

```shell
mkdir -p /etc/docker/
cat << 'EOF' >/etc/docker/daemon.json
{
    "log-driver": "json-file",
    "graph":"/data/docker",
    "log-opts": { "max-size": "100m"},
    "exec-opts": ["native.cgroupdriver=systemd"],
    "registry-mirrors": ["https://s3w3uu4l.mirror.aliyuncs.com"],
    "insecure-registries":["http://harbor.wzxmt.com"],
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 10,
    "storage-driver": "overlay2", 
    "storage-opts": ["overlay2.override_kernel_check=true"]
}
EOF
```

启动并设置开机启动

```shell
systemctl daemon-reload
systemctl enable --now docker
```

### 5.1 创建工作目录并拷贝二进制文件

#### 1.在所有worker node创建工作目录：

```shell
mkdir -p /etc/kubernetes/{pki,manifests} /opt/cni/bin /etc/cni/net.d /data/kubernetes/logs/{kubelet,kube-proxy}
```

#### 2.将kubelet与kube-proxy拷贝到所有worker node节点上：

```shell
cd kubernetes/server/bin
for n in n{1..3};do rsync -av kubelet kube-proxy $n:/usr/local/bin/;done
```

#### 3.拷贝证书到node

```
for n in n{1..3};do rsync -av /etc/kubernetes/pki/ca.pem $n:/etc/kubernetes/pki/;done
for n in n{1..3};do rsync -av /etc/kubernetes/{bootstrap-kubelet.kubeconfig,kube-proxy.kubeconfig} $n:/etc/kubernetes/;done
```

#### 4.下载cni插件并解压到所有节点上

```shell
wget https://github.com/containernetworking/plugins/releases/download/v0.8.5/cni-plugins-linux-amd64-v0.8.5.tgz
tar -zxf cni-plugins-linux-amd64-v0.8.5.tgz -C /opt/cni/bin
```

### 5.2 部署kubelet

#### 1. 配置参数文件

```shell
cat << 'EOF'  >/etc/kubernetes/kubelet-conf.yml
address: 0.0.0.0
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 2m0s
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.pem
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
cgroupDriver: systemd
cgroupsPerQOS: true
clusterDNS:
- 10.96.0.10
clusterDomain: cluster.local
configMapAndSecretChangeDetectionStrategy: Watch
containerLogMaxFiles: 5
containerLogMaxSize: 10Mi
contentType: application/vnd.kubernetes.protobuf
cpuCFSQuota: true
cpuCFSQuotaPeriod: 100ms
cpuManagerPolicy: none
cpuManagerReconcilePeriod: 10s
enableControllerAttachDetach: true
enableDebuggingHandlers: true
enforceNodeAllocatable:
- pods
eventBurst: 10
eventRecordQPS: 5
evictionHard:
  imagefs.available: 15%
  memory.available: 100Mi
  nodefs.available: 10%
  nodefs.inodesFree: 5%
evictionPressureTransitionPeriod: 5m0s
failSwapOn: true
fileCheckFrequency: 20s
hairpinMode: promiscuous-bridge
healthzBindAddress: 127.0.0.1
healthzPort: 10248
httpCheckFrequency: 20s
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80
imageMinimumGCAge: 2m0s
iptablesDropBit: 15
iptablesMasqueradeBit: 14
kind: KubeletConfiguration
kubeAPIBurst: 10
kubeAPIQPS: 5
makeIPTablesUtilChains: true
maxOpenFiles: 1000000
maxPods: 110
nodeLeaseDurationSeconds: 40
nodeStatusReportFrequency: 1m0s
nodeStatusUpdateFrequency: 10s
oomScoreAdj: -999
podPidsLimit: -1
port: 10250
registryBurst: 10
registryPullQPS: 5
resolvConf: /etc/resolv.conf
rotateCertificates: true
runtimeRequestTimeout: 2m0s
serializeImagePulls: true
staticPodPath: /etc/kubernetes/manifests
streamingConnectionIdleTimeout: 4h0m0s
syncFrequency: 1m0s
volumeStatsAggPeriod: 1m0s
EOF
```

#### 2. systemd管理kubelet

```shell
cat > /usr/lib/systemd/system/kubelet.service << EOF
[Unit]
Description=Kubernetes Kubelet
After=docker.service

[Service]
ExecStart=/usr/local/bin/kubelet \
  --runtime-cgroups=/systemd/system.slice \
  --kubelet-cgroups=/systemd/system.slice \
  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.kubeconfig \
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
  --config=/etc/kubernetes/kubelet-conf.yml \
  --network-plugin=cni \
  --cni-conf-dir=/etc/cni/net.d \
  --cni-bin-dir=/opt/cni/bin \
  --cert-dir=/etc/kubernetes/pki \
  --log-dir /data/kubernetes/logs/kubelet \
  --alsologtostderr=true \
  --logtostderr=false \
  --v=2 \
  --pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause-amd64:3.1
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
```

启动并设置开机启动

```shell
systemctl daemon-reload
systemctl enable --now kubelet
```

### 5.3 部署kube-proxy

systemd管理kube-proxy

```shell
cat > /usr/lib/systemd/system/kube-proxy.service << EOF
[Unit]
Description=Kubernetes Proxy
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-proxy \
  --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \
  --feature-gates=ServiceTopology=true,EndpointSlice=true \
  --masquerade-all=true \
  --proxy-mode=ipvs \
  --ipvs-min-sync-period=5s \
  --ipvs-sync-period=5s \
  --ipvs-scheduler=rr \
  --cluster-cidr=172.16.0.0/16 \
  --metrics-bind-address=0.0.0.0 \
  --alsologtostderr=true \
  --logtostderr=false \
  --log-dir /data/kubernetes/logs/kube-proxy \
  --v=2
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
```

启动并设置开机启动

```shell
systemctl daemon-reload
systemctl enable --now kube-proxy
```

### 5.7 新增加Worker Node

#### 1. 拷贝已部署好的Node相关文件到新节点

在master节点将Worker Node涉及文件拷贝到新节点10.0.0.41/73

```shell
scp /etc/kubernetes root@10.0.0.43:/etc/

scp -r /usr/lib/systemd/system/{kubelet,kube-proxy}.service root@10.0.0.43:/usr/lib/systemd/system
scp -r /opt/cni/ root@10.0.0.43:/opt/
```

#### 2. 删除kubelet证书和kubeconfig文件

```shell
rm -f /etc/kubernetes/pki/kubelet.kubeconfig 
rm -f /etc/kubernetes/pki/*kubelet*
```

> 注：这几个文件是证书申请审批后自动生成的，每个Node不同，必须删除重新生成。

#### 4. 启动并设置开机启动

```shell
systemctl daemon-reload
systemctl enable --now kube-proxy
systemctl enable --now kubelet
```

#### 5. 查看证书请求

```
kubectl get csr
```

可以看到node自动注册到master

#### 6. 查看Node状态

```shell
kubectl get node
NAME         STATUS     ROLES    AGE   VERSION
n1    Ready      <none>   12m   v1.18.3
n2    Ready      <none>   81s   v1.18.3
```
