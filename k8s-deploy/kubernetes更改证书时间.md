使用kubeadm安装的k8s，所有的证书都是放在 /etc/kubernetes/pki这个目录下的，我们可以查看每个证书的时间，会发现ca证书除外，其他组件证书都是默认一年有效期，ca类型的证书的有效期为10年。

```
kubeadm alpha certs check-expiration

CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 Dec 15, 2021 09:27 UTC   337d                                    no      
apiserver                  Dec 15, 2021 09:27 UTC   337d            ca                      no      
apiserver-etcd-client      Dec 15, 2021 09:27 UTC   337d            etcd-ca                 no      
apiserver-kubelet-client   Dec 15, 2021 09:27 UTC   337d            ca                      no      
controller-manager.conf    Dec 15, 2021 09:27 UTC   337d                                    no      
etcd-healthcheck-client    Dec 15, 2021 09:27 UTC   337d            etcd-ca                 no      
etcd-peer                  Dec 15, 2021 09:27 UTC   337d            etcd-ca                 no      
etcd-server                Dec 15, 2021 09:27 UTC   337d            etcd-ca                 no      
front-proxy-client         Dec 15, 2021 09:27 UTC   337d            front-proxy-ca          no      
scheduler.conf             Dec 15, 2021 09:27 UTC   337d                                    no      

CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME   EXTERNALLY MANAGED
ca                      Dec 13, 2030 09:27 UTC   9y              no      
etcd-ca                 Dec 13, 2030 09:27 UTC   9y              no      
front-proxy-ca          Dec 13, 2030 09:27 UTC   9y              no
```

服务器的k8s master上需要安装两个工具git和go (这里就省略了)

```
wget https://golang.org/dl/go1.16.5.linux-amd64.tar.gz
tar xf go1.16.5.linux-amd64.tar.gz -C /usr/local/
export PATH=$PATH:/usr/local/go/bin
```

下载源码

```
git clone -b v1.18.5 --depth=1 https://github.com/kubernetes/kubernetes.git
cd kubernetes
```

修改配置

```
# 修改  cmd/kubeadm/app/constans/constans.go 文件
# 找到 CertificateValidity = time.Hour * 24 * 365, 修改为下面一行内容
CertificateValidity = time.Hour * 24 * 365 * 10
```

#编译kubeadm，编译完生成_output目录

```
cd kubernetes/
make WHAT=cmd/kubeadm

+++ [0112 17:59:21] Building go targets for linux/amd64:
    ./vendor/k8s.io/code-generator/cmd/deepcopy-gen
+++ [0112 17:59:39] Building go targets for linux/amd64:
    ./vendor/k8s.io/code-generator/cmd/defaulter-gen
+++ [0112 17:59:53] Building go targets for linux/amd64:
    ./vendor/k8s.io/code-generator/cmd/conversion-gen
+++ [0112 18:00:19] Building go targets for linux/amd64:
    ./vendor/k8s.io/kube-openapi/cmd/openapi-gen
+++ [0112 18:00:41] Building go targets for linux/amd64:
    ./vendor/github.com/go-bindata/go-bindata/go-bindata
warning: ignoring symlink /usr/local/src/kubernetes/_output/local/go/src/k8s.io/kubernetes
go: warning: "k8s.io/kubernetes/vendor/github.com/go-bindata/go-bindata/..." matched no packages
+++ [0112 18:00:42] Building go targets for linux/amd64:
    cmd/kubeadm
```

备份kubeadm,替换成新的

```
mv /usr/bin/kubeadm /usr/bin/kubeadm.old
cp _output/bin/kubeadm /usr/bin/kubeadm
```

备份之前的证书

```
cp -rf /etc/kubernetes/pki/  /etc/kubernetes/pki.old
```

重新生成证书 

```
kubeadm alpha certs renew all

[renew] Reading configuration from the cluster...
certificate embedded in the kubeconfig file for the admin to use and for kubeadm itself renewed
certificate for serving the Kubernetes API renewed
certificate the apiserver uses to access etcd renewed
certificate for the API server to connect to kubelet renewed
certificate embedded in the kubeconfig file for the controller manager to use renewed
certificate for liveness probes to healthcheck etcd renewed
certificate for etcd nodes to communicate with each other renewed
certificate for serving etcd renewed
certificate for the front proxy client renewed
certificate embedded in the kubeconfig file for the scheduler manager to use renewed
```

再次查看组件中的证书有效时间，已经为10年了  

```
kubeadm alpha certs check-expiration

CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 Jan 10, 2031 10:10 UTC   9y                                      no      
apiserver                  Jan 10, 2031 10:10 UTC   9y              ca                      no      
apiserver-etcd-client      Jan 10, 2031 10:10 UTC   9y              etcd-ca                 no      
apiserver-kubelet-client   Jan 10, 2031 10:10 UTC   9y              ca                      no      
controller-manager.conf    Jan 10, 2031 10:10 UTC   9y                                      no      
etcd-healthcheck-client    Jan 10, 2031 10:10 UTC   9y              etcd-ca                 no      
etcd-peer                  Jan 10, 2031 10:10 UTC   9y              etcd-ca                 no      
etcd-server                Jan 10, 2031 10:10 UTC   9y              etcd-ca                 no      
front-proxy-client         Jan 10, 2031 10:10 UTC   9y              front-proxy-ca          no      
scheduler.conf             Jan 10, 2031 10:10 UTC   9y                                      no      

CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME   EXTERNALLY MANAGED
ca                      Dec 13, 2030 09:27 UTC   9y              no      
etcd-ca                 Dec 13, 2030 09:27 UTC   9y              no      
front-proxy-ca          Dec 13, 2030 09:27 UTC   9y              no
```
