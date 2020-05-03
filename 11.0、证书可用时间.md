# 证书可用时限

## 1、go 环境部署

[go官网](https://golang.google.cn/dl/#stable)

下载稳定版二进制，并解压

```bash
wget https://dl.google.com/go/go1.14.1.linux-amd64.tar.gz
tar xf go1.14.1.linux-amd64.tar.gz -C /usr/local/src/
```

添加环境变量

```bash
echo 'export PATH=$PATH:/usr/local/drc/go/bin' >>/etc/profile
source /etc/profile
```

## 2、下载kubernetes

选择对应版本**[kubernetes](https://github.com/kubernetes/kubernetes)**源码包

```bash
mkdir /usr/local/src/kubernetes/ -p
cd /usr/local/src/kubernetes
wget https://dl.k8s.io/v1.17.4/kubernetes-src.tar.gz
tar xf kubernetes-src.tar.gz
```

## 3、修改 Kubeadm 源码包更新证书策略

kubeadm 1.14 版本之前，修改staging/src/k8s.io/client-go/util/cert/cert.go
kubeadm 1.14版本之 后，修改cmd/kubeadm/app/util/pkiutil/pki_helpers.go

```bash
#添加可用时间
sed  -ri '/ cryptorand.Int/a\      i  const duration100y = time.Hour * 24 * 365 * 100' cmd/kubeadm/app/util/pkiutil/pki_helpers.go
#修改可用时间
sed  -r '/NotAfter:/s#(.*)(Add\()(.*)(\).U)#\1\2duration100y\4#' cmd/kubeadm/app/util/pkiutil/pki_helpers.go
```

## 4、更新 kubeadm

```bash
# 将 kubeadm 进行替换
cd /usr/local/src/kubernetes/_output/bin
mv /usr/bin/kubeadm /usr/bin/kubeadm.old
mv kubeadm /usr/bin/
chmod a+x /usr/bin/kubeadm
```

## 5、查看当前证书使用期限

```bash
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep Not
           Not Before: Mar 24 03:39:27 2020 GMT
           Not After : Mar 24 03:39:27 2021 GMT
```

## 6、更新各节点证书至 Master 节点

```
cp -r /etc/kubernetes/pki /etc/kubernetes/pki.old
cd /etc/kubernetes/pki
```

如果没有初始化配置文件，需要生成初始化文件

```bash
cat << EOF > /root/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
kubernetesVersion: v1.17.4 # 指定版本
imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers
controlPlaneEndpoint: "10.0.0.31:6443"
networking:
  dnsDomain: cluster.local
  serviceSubnet:  10.1.0.0/16 #用于指定SVC的网络范围；
  podSubnet: 10.244.0.0/16 # 计划使用flannel网络插件，指定pod网段及掩码
EOF
```

更新证书

```bash
kubeadm alpha certs renew all --config=/root/kubeadm-config.yaml
```

## 7、查看更新后证书使用期限

```bash
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep Not
            Not Before: Mar 24 03:39:27 2020 GMT
            Not After : Mar  2 06:02:30 2120 GMT
```

## 8、HA集群其余 mater 节点证书更新

备份其余master证书

```bash
cat<< EOF >~/backup_master_ssl.sh
#!/bin/bash
USER=root
for n in `/root/master_ip.txt`
do 
  ssh $n "cd /etc/kubernetes && cp -r pki pki_bak && cp admin.conf admin.conf.bak"
done
```

同步证书到其他master节点

```bash
cat<< EOF >~/certificate.sh
#!/bin/bash
USER=root
for host in `/root/master_ip.txt`
do
    scp /etc/kubernetes/pki/ca.crt "${USER}"@$host:/etc/kubernetes/pki/
    scp /etc/kubernetes/pki/ca.key "${USER}"@$host:/etc/kubernetes/pki/
    scp /etc/kubernetes/pki/sa.key "${USER}"@$host:/etc/kubernetes/pki/
    scp /etc/kubernetes/pki/sa.pub "${USER}"@$host:/etc/kubernetes/pki/
    scp /etc/kubernetes/pki/front-proxy-ca.crt "${USER}"@$host:/etc/kubernetes/pki/
    scp /etc/kubernetes/pki/front-proxy-ca.key "${USER}"@$host:/etc/kubernetes/pki/
    scp /etc/kubernetes/pki/etcd/ca.crt "${USER}"@$host:/etc/kubernetes/pki/etcd/ca.crt
    scp /etc/kubernetes/pki/etcd/ca.key "${USER}"@$host:/etc/kubernetes/pki/etcd/ca.key
    scp /etc/kubernetes/admin.conf "${USER}"@$host:/etc/kubernetes/
done
EOF
```

