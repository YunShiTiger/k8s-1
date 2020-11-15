## [什么是Calico?](https://www.projectcalico.org/)

Calico是针对容器，虚拟机和基于主机的本机工作负载的开源网络和网络安全解决方案。
Calico支持广泛的平台，包括Kubernetes，OpenShift，Docker EE，OpenStack和裸机服务。
Calico将灵活的网络功能与无处不在的安全性实施相结合，以提供具有本地Linux内核性能和真正的云原生可扩展性的解决方案。
Calico为开发人员和集群运营商提供了一致的经验和功能集，无论是在公共云中还是本地运行，在单个节点上还是在数千个节点集群中运行。

------

## calico组件：

整合ks8/calico一共有三个组件：

1.每个节点运行一个calico/node容器；包含了calico路由必须的bgp客户端

2.calico-cni网络插件的二进制文件（这是两个二进制可执行文件和配置文件的组合）；直接与kubelet集成，运行在每节点从而发现被创建的容器，添加容器到calico网络

3.如果想要使用NetworkPolicy，需要安装Calico policy controller；实现了NetworkPolicy.**

## 两种网络模式

### **IPIP网络**：

​	**流量：**tunlo设备封装数据，形成隧道，承载流量。

​	**适用网络类型：**适用于互相访问的pod不在同一个网段中，跨网段访问的场景。外层封装的ip能够解决跨网段的路由问题。

​	**效率：**流量需要tunl0设备封装，效率略低。

### **BGP网络**：

​	**流量：**使用路由信息导向流量

​	**适用网络类型：**适用于互相访问的pod在同一个网段，适用于大型网络。

​	**效率：**原生hostGW，效率高。

------

## 部署安装

**1）**确保Calico可以在主机上进行管理`cali`和`tunl`接口，如果主机上存在NetworkManage，请配置NetworkManager。

NetworkManager会为默认网络名称空间中的接口操纵路由表，在该默认名称空间中，固定了Calico veth对以连接到容器，这可能会干扰Calico代理正确路由的能力。

在以下位置创建以下配置文件，以防止NetworkManager干扰接口：

```bash
cat << 'EOF' >/etc/NetworkManager/conf.d/calico.conf
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:tunl*
EOF
```

**2）**下载calica.yaml部署文件,修改配置

```bash
curl https://docs.projectcalico.org/manifests/calico-etcd.yaml -o calico.yaml
```

修改文件

```bash
data:  
  etcd-ca: (cat ca.pem | base64 | tr -d '\n') #将输出结果填写在这里
  etcd-key: (cat etcd-key.pem | base64 | tr -d '\n') #将输出结果填写在这里
  etcd-cert: (cat etcd.pem  | base64 | tr -d '\n') #将输出结果填写在这里
....
  etcd_endpoints: "https://10.0.0.31:2379,https://10.0.0.32:2379,https://10.0.0.33:2379"
....
#You must also populate the Secret below with these files.
  etcd_ca: "/calico-secrets/etcd-ca"
  etcd_cert: "/calico-secrets/etcd-cert"
  etcd_key: "/calico-secrets/etcd-key"
....
# 必须要修改，根据实际需求，与集群内部ip range保持一致
- name: CALICO_IPV4POOL_CIDR
  value: "172.16.0.0/16"
....
# Enable IPIP
- name: CALICO_IPV4POOL_IPIP
  value: "Never"
```

**3)下载所需镜像(建议下载后 推到自己的镜像仓库)**

```
cat calico.yaml |grep image
          image: calico/cni:v3.16.3
          image: calico/pod2daemon-flexvol:v3.16.3
          image: calico/node:v3.16.3
          image: calico/kube-controllers:v3.16.3
```

**4)部署calico**

```
kubectl apply -f calico.yaml
```

**5）**使用以下命令确认所有Pod正在运行。

```bash
watch kubectl get pods --all-namespaces
```

等到每个calico全部Running即可。

```
NAMESPACE    NAME                                       READY  STATUS   RESTARTS  AGE
kube-system  calico-kube-controllers-6ff88bf6d4-tgtzb   1/1    Running  0         2m45s
kube-system  calico-node-24h85                          1/1    Running  0         2m43s
kube-system  calico-node-45k48                          1/1    Running  0         2m43s
```

按CTRL + C退出watch。

**6）**如果是切换网络插件，需要清理每个节点上之前残留的路由表和网桥，以避免和calico冲突。

```
ip link
ip link delete flannel.1
ip route
ip route delete 10.244.0.0/24 via 10.4.7.21 dev eth0 
```

