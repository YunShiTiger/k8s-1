## 1. 准备服务器

| 系统类型   | IP地址     | 节点角色 | CPU  | Memory | Hostname |
| :--------- | ---------- | -------- | ---- | ------ | -------- |
| pod        | 10.0.0.150 | vip      |      |        |          |
| centos7-64 | 10.0.0.31  | m1       | 1    | 2G     | m1       |
| centos7-64 | 10.0.0.32  | m2       | 1    | 2G     | m2       |
| centos7-64 | 10.0.0.41  | n1       | 1    | 2G     | n1       |
| centos7-64 | 10.0.0.42  | n2       | 1    | 2G     | n2       |
| centos7-64 | 10.0.0.43  | n3       | 1    | 2G     | n3       |

## 2. 系统设置(所有节点）

#### 1 配置hosts文件

配置host，使每个Node都可以通过名字解析到ip地址

```bash
cat<< EOF >>/etc/hosts
10.0.0.31 m1
10.0.0.32 m2
10.0.0.41 n1
10.0.0.42 n2
10.0.0.43 n3
EOF
```

#### 2 关闭、禁用防火墙、selinux与swap

**关闭防火墙**

```bash
firewall-cmd --state
systemctl stop firewalld.service
systemctl disable firewalld.service
```

**关闭selinux**

```bash
setenforce 0
sed -i "s/^SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
```

**关闭swap**

```bash
swapoff -a
sed -i 's/.*swap.*/#&/' /etc/fstab
```

因为这里本次用于测试两台主机上还运行其他服务，关闭swap可能会对其他服务产生影响，所以这里修改kubelet的配置去掉这个限制。 使用kubelet的启动参数--fail-swap-on=false去掉必须关闭swap的限制，修改vim /etc/sysconfig/kubelet，加入：

```bash
cat<< EOF >/etc/sysconfig/kubelet
KUBELET_EXTRA_ARGS=--fail-swap-on=false
EOF
```

#### 3 更新 yum 源

```bash
cd /etc/yum.repos.d
mv CentOS-Base.repo CentOS-Base.repo.bak
mv epel.repo  epel.repo.bak
curl https://mirrors.aliyun.com/repo/Centos-7.repo -o CentOS-Base.repo 
curl https://mirrors.aliyun.com/repo/epel-7.repo -o epel.repo
cd -
```

#### 4 内核参数优化

```bash
cat << EOF >/etc/sysctl.d/99-sysctl.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0 # 禁止使用 swap 空间，只有当系统 OOM 时才允许使用它
vm.overcommit_memory=1 # 不检查物理内存是否够用
vm.panic_on_oom=0 # 开启 OOM
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF
```

加载内核

```
sysctl -p
```

#### 5 开启ipvs的前置条件

由于ipvs已经加入到了内核的主干，所以为kube-proxy开启ipvs的前提需要加载以下的内核模块：

```bash
cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
EOF
chmod 755 /etc/sysconfig/modules/ipvs.modules
bash /etc/sysconfig/modules/ipvs.modules
lsmod|egrep "ip_vs|nf_conntrack_ipv4"
```

上面脚本创建了的/etc/sysconfig/modules/ipvs.modules文件，保证在节点重启后能自动加载所需模块。

各个节点上已经安装了ipset软件包与管理工具

```bash
yum install -y ipset ipvsadm
```

如果以上前提条件如果不满足，则即使kube-proxy的配置开启了ipvs模式，也会退回到iptables模式。

#### 6 调整系统时区

```bash
# 设置系统时区为中国/上海
timedatectl set-timezone Asia/Shanghai
# 将当前的 UTC 时间写入硬件时钟timedatectl set-local-rtc 0
# 重启依赖于系统时间的服务systemctl restart rsyslog
systemctl restart crond
```

#### 7 设置journald

```bash
mkdir /var/log/journal # 持久化保存日志的目录
mkdir /etc/systemd/journald.conf.d
cat << EOF >/etc/systemd/journald.conf.d/99-prophet.conf
[Journal]
# 持久化保存到磁盘
Storage=persistent
# 压缩历史日志
Compress=yes
SyncIntervalSec=5m
RateLimitInterval=30s
RateLimitBurst=1000
# 最大占用空间 10G
SystemMaxUse=10G
# 单日志文件最大 200M
SystemMaxFileSize=200M
# 日志保存时间 2 周
MaxRetentionSec=2week
# 不将日志转发到 
syslogForwardToSyslog=no
EOF
systemctl restart systemd-journald
```

#### 8 升级系统内核

CentOS 7.x 系统自带的 3.10.x 内核存在一些 Bugs，导致运行的 Docker、Kubernetes 不稳定 

```bash
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
```

 安装完成后检查 /boot/grub2/grub.cfg 中对应内核 menuentry 中是否包含 initrd16 配置，如果没有，再安装一次！

```bash
yum --enablerepo=elrepo-kernel install -y kernel-lt
```

设置开机从新内核启动

```bash
grub2-set-default 0
```

查看内核

```bash
uname -r
4.4.218-1.el7.elrepo.x86_64
```

#### 9 关闭 NUMA

备份grub

```bash
cp /etc/default/grub{,.bak}
```

在 GRUB_CMDLINE_LINUX 一行添加 `numa=off` 参数，如下所示：

```bash
GRUB_CMDLINE_LINUX="crashkernel=auto rd.lvm.lv=centos/root rhgb quiet numa=off"
```

加载内核

```bash
grub2-mkconfig -o /boot/grub2/grub.cfg
```

## 3. 安装docker(node节点）

### 1 yum安装

#### 1 安装依赖

```bash
yum install -y yum-utils device-mapper-persistent-data lvm2
```

#### 2 配置docker源

```bash
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum makecache fast
rpm --import https://mirrors.aliyun.com/docker-ce/linux/centos/gpg
```

#### 3 查看docker版号

```bash
yum list docker-ce.x86_64  --showduplicates |sort -r
```

 Kubernetes 1.16当前支持的docker版本列表是 Docker版本1.13.1、17.03、17.06、17.09、18.06、18.09 

#### 4 安装 docker

```bash
yum makecache fast
yum install -y docker-ce-19.03.15-3.el7
```

### 2 二进制安装

#### 1 下载地址

```bash
https://download.docker.com/linux/static/stable/x86_64/
```

#### 2 解压安装

```bash
tar zxvf docker-18.09.6.tgz
mv docker/* /usr/bin
mkdir /etc/docker
mkdir -p /data/docker
mv daemon.json /etc/docker
mv docker.service /usr/lib/systemd/system
```

#### 3 systemctl管理docker

```bash
cat > /usr/lib/systemd/system/docker.service << EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target firewalld.service
[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
#TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process
[Install]
WantedBy=multi-user.target
EOF
```

### 3 配置所有ip的数据包转发

```bash
#找到ExecStart=xxx，在这行下面加入一行，内容如下：(k8s的网络需要)
sed -i.bak '/ExecStart/a\ExecStartPost=/sbin/iptables -I FORWARD -s 0.0.0.0/0 -j ACCEPT' /lib/systemd/system/docker.service
```

### 4 docker基础优化

```bash
mkdir -p /etc/docker/
cat << EOF >/etc/docker/daemon.json
{
    "log-driver": "json-file",
    "graph":"/data/docker",
    "log-opts": { "max-size": "100m"},
    "exec-opts": ["native.cgroupdriver=systemd"],
    "registry-mirrors": ["https://s3w3uu4l.mirror.aliyuncs.com"],
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 10,
    "storage-driver": "overlay2", 
    "storage-opts": ["overlay2.override_kernel_check=true"]
}
EOF
```

### 5 启动服务

```bash
#设置 docker 开机服务启动
systemctl enable --now docker.service 
```

## 4. 安装kubeadm组件

#### 1 配置kubernetes阿里源

```bash
cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
```

#### 2  查看kubeadm、kubelet和kubectl版号

```bash
yum makecache fast
yum list kubeadm kubelet kubectl  --showduplicates
```

#### 3  各节点安装kubernetes

```bash
#master
yum install -y kubelet-1.18.0-0 kubeadm-1.18.0-0 kubectl-1.18.0-0
systemctl enable kubelet 
#node
yum install -y kubelet kubeadm
systemctl enable kubelet
```

注：因为kubeadm默认生成的证书有效期只有一年，所以kubeadm等安装成功后，可以用编译好的kubeadm替换掉默认的kubeadm。后面初始化k8s生成的证书都是100年。

## 5. kube-vip HA集群

#### 1 [kube-vip](https://kube-vip.io/install_static/) 架构简介

kube-vip 有许多功能设计选择提供高可用性或网络功能，作为VIP/负载平衡解决方案的一部分。

**Cluster**
kube-vip 建立了一个多节点或多模块的集群来提供高可用性。在 ARP 模式下，会选出一个领导者，这个节点将继承虚拟 IP 并成为集群内负载均衡的领导者，而在 BGP 模式下，所有节点都会通知 VIP 地址。

当使用 ARP 或 layer2 时，它将使用领导者选举，当然也可以使用 raft 集群技术，但这种方法在很大程度上已经被领导者选举所取代，特别是在集群中运行时。

**虚拟IP**
集群中的领导者将分配 vip，并将其绑定到配置中声明的选定接口上。当领导者改变时，它将首先撤销 vip，或者在失败的情况下，vip 将直接由下一个当选的领导者分配。

当 vip 从一个主机移动到另一个主机时，任何使用 vip 的主机将保留以前的 vip <-> MAC 地址映射，直到 ARP 过期（通常是30秒）并检索到一个新的 vip <-> MAC 映射，这可以通过使用无偿的 ARP 广播来优化。

**ARP**
kube-vip可以被配置为广播一个无偿的 arp（可选），通常会立即通知所有本地主机 vip <-> MAC 地址映射已经改变。

#### 2 部署kube-vip

添加hosts解析

```
echo "10.0.0.31 m1" >>/etc/hosts
```

各master节点部署静态pod

```bash
mkdir -p /etc/kubernetes/manifests
docker run --network host -v /etc/hosts:/etc/hosts --rm ghcr.io/kube-vip/kube-vip:v0.3.8 manifest pod \
    --interface eth0 \
    --vip 10.0.0.150 \
    --controlplane \
    --services \
    --arp \
    --leaderElection --startAsLeader|tee /etc/kubernetes/manifests/kube-vip.yaml
```

会生成以下配置

```yaml
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  name: kube-vip
  namespace: kube-system
spec:
  containers:
  - args:
    - manager
    env:
    - name: vip_arp
      value: "true"
    - name: vip_interface
      value: eth0
    - name: port
      value: "6443"
    - name: vip_cidr
      value: "32"
    - name: cp_enable
      value: "true"
    - name: cp_namespace
      value: kube-system
    - name: vip_ddns
      value: "false"
    - name: svc_enable
      value: "true"
    - name: vip_leaderelection
      value: "true"
    - name: vip_leaseduration
      value: "5"
    - name: vip_renewdeadline
      value: "3"
    - name: vip_retryperiod
      value: "1"
    - name: vip_address
      value: 10.0.0.150
    image: ghcr.io/kube-vip/kube-vip:v0.3.8
    imagePullPolicy: Always
    name: kube-vip
    resources: {}
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
        - SYS_TIME
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/admin.conf
    name: kubeconfig
status: {}
```

## 6.  初始化master

#### 1 始化m1

初始化之前检查haproxy是否正在运行，keepalived是否正常运作 ：

 查看所需的镜像 

```bash
kubeadm --kubernetes-version=1.18.0 config images list
#所需镜像
k8s.gcr.io/kube-apiserver:v1.18.0
k8s.gcr.io/kube-controller-manager:v1.18.0
k8s.gcr.io/kube-scheduler:v1.18.0
k8s.gcr.io/kube-proxy:v1.18.0
k8s.gcr.io/pause:3.2
k8s.gcr.io/etcd:3.4.3-0
k8s.gcr.io/coredns:1.6.7
```

 因为k8s.gcr.io地址在国内是不能访问的，能上外网可以通过以下命令提前把镜像pull下来 

```
kubeadm config images pull
```

因为不能翻墙,使用国内镜像，直接在命令行指定相应配置

```bash
kubeadm init --kubernetes-version=1.18.0 \
--apiserver-advertise-address=0.0.0.0 \
--image-repository registry.aliyuncs.com/google_containers \
--control-plane-endpoint 10.0.0.150:6443 \
--service-cidr=10.96.0.0/16 \
--pod-network-cidr=172.16.0.0/16 \
--upload-certs
```

初始化成功后，会看到大概如下提示，下面信息先保留。后续添加master节点，添加node节点需要用到

```bash
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of the control-plane node running the following command on each as root:

  kubeadm join 10.0.0.150:6443 --token bnxc4v.liv08h0zwe2iunem \
    --discovery-token-ca-cert-hash sha256:74058be8e7e896c0e48fca9c828a2b46bd41637f44595b1a5ad7aedaf9e4bc19 \
    --control-plane --certificate-key 9c6b044ac38318174c647c3fa93e64809b193df42e392ebc6695b93718e307cf

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 10.0.0.150:6443 --token bnxc4v.liv08h0zwe2iunem \
    --discovery-token-ca-cert-hash sha256:74058be8e7e896c0e48fca9c828a2b46bd41637f44595b1a5ad7aedaf9e4bc19
```

上面记录了完成的初始化输出的内容，根据输出的内容基本上可以看出手动初始化安装一个Kubernetes集群所需要的关键步骤。 其中有以下关键内容：

- [kubelet-start] 生成kubelet的配置文件”/var/lib/kubelet/config.yaml”
- [certs]生成相关的各种证书
- [kubeconfig]生成相关的kubeconfig文件
- [control-plane]使用/etc/kubernetes/manifests目录中的yaml文件创建apiserver、controller-manager、scheduler的静态pod
- [bootstraptoken]生成token记录下来，后边使用kubeadm join往集群中添加节点时会用到
- 下面的命令是配置常规用户如何使用kubectl访问集群：

按提示执行如下命令，kubectl就能使用了

```bash
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

如果集群初始化遇到问题，可以使用下面的命令进行清理：

```bash
kubeadm reset -f
ifconfig cni0 down
ip link delete cni0
ifconfig kube-ipvs0 down 
ip link delete kube-ipvs0
ipvsadm --clear
ifconfig flannel.1 down
ip link delete flannel.1
rm -rf /var/lib/cni /etc/kubernetes /root/.kube /etc/cni/net.d
```

####  2 安装Pod Network

获取所有pod状态

```bash
[root@m1 ~]# kubectl get pods -n kube-system
NAMESPACE     NAME                          READY   STATUS    RESTARTS   AGE
kube-system   coredns-7ff77c879f-g56zx     0/1     Pending   0          29s
kube-system   coredns-7ff77c879f-vbx8c     0/1     Pending   0          29s
kube-system   etcd-m1                      1/1     Running   0          39s
kube-system   kube-apiserver-m1            1/1     Running   0          39s
kube-system   kube-controller-manager-m1   1/1     Running   0          39s
kube-system   kube-proxy-qgd42             1/1     Running   0          30s
kube-system   kube-scheduler-m1            1/1     Running   0          39s
kube-system   kube-vip-m1                  1/1     Running   0          39s
```

coredns处于Pending状态，journalctl -f -u kubelet.service日志

```bash
Nov 13 20:32:20 m1 kubelet[7791]: W1113 20:32:20.055543    7791 cni.go:237] Unable to update cni config: no networks found in /etc/cni/net.d
Nov 13 20:32:23 m1 kubelet[7791]: E1113 20:32:23.440739    7791 kubelet.go:2187] Container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady message:docker: network plugin is not ready: cni config uninitialized
```

创建kube-flannel pod

网络不好，可以先下下来，再执行

```bash
kubectl apply -f kube-flannel.yml
kubectl apply -f kube-flannel-rbac.yml
```

**kube-flannel**

```bash
wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

修改net-conf.json

```bash
 "Network": "172.16.0.0/16"
```

部署

```
kubectl apply -f kube-flannel.yml
```

确保所有的Pod都处于Running状态

```bash
[root@m1 ~]# kubectl get pods -n kube-system
NAME                         READY   STATUS    RESTARTS   AGE
coredns-58cc8c89f4-dsdlc     1/1     Running   0          45m
coredns-58cc8c89f4-w9plv     1/1     Running   0          45m
etcd-m1                      1/1     Running   0          44m
kube-apiserver-m1            1/1     Running   0          44m
kube-controller-manager-m1   1/1     Running   0          44m
kube-flannel-ds-amd64-mf66l  1/1     Running   0          5m14s
kube-proxy-76ldd             1/1     Running   0          45m
kube-scheduler-m1            1/1     Running   0          44m
kube-system   kube-vip-m1    1/1     Running   0          45mm
```

查看一下集群状态，确认个组件都处于healthy状态：

```bash
[root@m1 ~]# kubectl get cs
NAME                 STATUS    MESSAGE             ERROR
controller-manager   Healthy   ok
scheduler            Healthy   ok
etcd-0               Healthy   {"health":"true"}
```

#### 3 测试集群DNS是否可用

```bash
kubectl run curl --rm --image=radial/busyboxplus:curl -it
```

**发现创建的pod节点一直处于Pending状态，这时候需要去污(重要)**

```bash
kubectl taint nodes --all node-role.kubernetes.io/master-
```

进入后执行nslookup kubernetes.default确认解析正常:

```bash
[root@k8s ~]# kubectl run curl --rm --image=radial/busyboxplus:curl -it
If you don't see a command prompt, try pressing enter.
[ root@curl:/ ]$ nslookup kubernetes.default
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes.default
Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local
```

确定外部连接

```bash
[ root@curl:/ ]$ ping www.baidu.com
PING www.baidu.com (14.215.177.38): 56 data bytes
64 bytes from 14.215.177.38: seq=0 ttl=127 time=8.585 ms
64 bytes from 14.215.177.38: seq=1 ttl=127 time=9.764 ms
64 bytes from 14.215.177.38: seq=2 ttl=127 time=9.144 ms
```

#### 4 Kubernetes集群中添加Node节点

默认token的有效期为24小时，当过期之后，该token就不可用了，以后加入节点需要新token

 master重新生成新的token

```bash
[root@m1 ~]# kubeadm token create
tkxyys.8ilumwddiexjd8g2

[root@m1 ~]# kubeadm token list
TOKEN                     TTL       EXPIRES                     USAGES                   DESCRIPTION   EXTRA GROUPS
tkxyys.8ilumwddiexjd8g2   23h       2019-07-10T21:19:17+08:00   authentication,signing   <none>        system:bootstrappers:kubeadm:default-node-token
```

获取ca证书`sha256`编码hash值

```bash
[root@master ~]# openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt|openssl rsa -pubin -outform der 2>/dev/null|openssl dgst -sha256 -hex|awk '{print $NF}'
2e4ec2c6267389ccc2aa293a61ab474b0304778d56dfb07f5105a709d3b798e6
```

添加node节点

```bash
kubeadm join 10.0.0.150:6443 --token 4qcl2f.gtl3h8e5kjltuo0r \
--discovery-token-ca-cert-hash sha256:7ed5404175cc0bf18dbfe53f19d4a35b1e3d40c19b10924275868ebf2a3bbe6e \
--ignore-preflight-errors=all
```

n1加入集群很是顺利，下面在master节点上执行命令查看集群中的节点：

```bash
[root@m1 ~]# kubectl get node
NAME     STATUS   ROLES    AGE   VERSION
master   Ready    master   18m   v1.15.0
n1 <none>   master   11m   v1.15.0
```

节点没有ready 一般是由于flannel 插件没有装好，可以通过查看kube-system 的pod 验证

#### 5 如何从集群中移除Node

如果需要从集群中移除n1这个Node执行下面的命令：

在master节点上执行：

```bash
kubectl drain n1 --delete-local-data --force --ignore-daemonsets
```

在n1上执行：

```bash
kubeadm reset -f
ifconfig cni0 down
ip link delete cni0
ifconfig kube-ipvs0 down 
ip link delete kube-ipvs0
ipvsadm --clear
ifconfig flannel.1 down
ip link delete flannel.1
rm -rf /var/lib/cni /etc/kubernetes
```

在master上执行：

```bash
kubectl delete node n1
```

不在master节点上操作集群，而是在其他工作节点上操作集群:

需要将master节点上面的kubernetes配置文件拷贝到当前节点上，然后执行kubectl命令:

```bash
#将主配置拉取到本地scp root@n1:/etc/kubernetes/admin.conf /etc/kubernetes/
#常规用户如何使用kubectl访问集群配置mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

移除kubelet

```bash
yum remove -y kubeadm kubelet kubectl
```

#### 6 添加master

使用之前生成的提示信息，在m2执行，就能添加一个master

```bash
kubeadm join 10.0.0.150:6443 --token 66jnza.vwvw9xp6hwkwmrtz \
    --discovery-token-ca-cert-hash sha256:46c600824f2a5c4c29ba3f0b5667c3728604ab64a40d880de8f89eaceb9b6531 \
    --experimental-control-plane --certificate-key 0a050aa3d2ce1b9366a66d5fe01946fa249340dd5088b07a05d37f465ed41150
```


执行完如上初始化命令，第二个master节点就能添加到集群

提示信息里面有如下内容，应该是之前指定参数上传的证书2个小时后会被删除，可以使用命令重新上传证书

```bash
Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use 
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.
```

#### 7 kube-proxy开启ipvs

修改ConfigMap的kube-system/kube-proxy中的config.conf，mode: “ipvs”

```bash
kubectl edit cm kube-proxy -n kube-system
```

重启各个节点上的kube-proxy pod：

```bash
kubectl get pod -n kube-system | grep kube-proxy | awk '{system("kubectl delete pod "$1" -n kube-system")}'
```

查看kube-proxy pod

```bash
kubectl get pod -n kube-system | grep kube-proxy

kube-proxy-62jb4                       1/1     Running   0          2m54s
kube-proxy-7k4bc                       1/1     Running   0          2m13s
kube-proxy-hrs9n                       1/1     Running   0          2m29s
kube-proxy-jk85p                       1/1     Running   0          3m17s
kube-proxy-lpdsp                       1/1     Running   0          2m45s
```

查看kube-proxy日志

```bash
 kubectl logs `kubectl get pod -n kube-system | grep kube-proxy|awk 'NR==1{print $1}'` -n kube-system
 
I1106 15:33:46.141633       1 server_others.go:170] Using ipvs Proxier.
W1106 15:33:46.142109       1 proxier.go:401] IPVS scheduler not specified, use rr by default
I1106 15:33:46.142408       1 server.go:534] Version: v1.15.0
I1106 15:33:46.161386       1 conntrack.go:52] Setting nf_conntrack_max to 131072
I1106 15:33:46.162251       1 config.go:187] Starting service config controller
I1106 15:33:46.162278       1 controller_utils.go:1029] Waiting for caches to sync for service config controller
I1106 15:33:46.162300       1 config.go:96] Starting endpoints config controller
I1106 15:33:46.162324       1 controller_utils.go:1029] Waiting for caches to sync for endpoints config controller
I1106 15:33:46.266148       1 controller_utils.go:1036] Caches are synced for endpoints config controller
I1106 15:33:46.463107       1 controller_utils.go:1036] Caches are synced for service config controller
```

日志中打印出了Using ipvs Proxier，说明ipvs模式已经开启。

## 7.  报错解决

1、Kubernetes报错Failed to get system container stats for "/system.slice/kubelet.service"

 在kubelet配置文件10-kubeadm.conf中的 Environment中添加"--runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice"

```bash
sed -ri.bak "s#(.*)(kubelet\.conf)#\1\2 --runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice#g" /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
```

然后重启

```bash
systemctl daemon-reload
systemctl restart kubelet.service
journalctl -f -u kubelet.service
```

2、清除退出容器

```bash
docker rm `docker ps -a|grep 'Exited'|awk '{print $1}'`
```

到此，k8s集群部署完毕

