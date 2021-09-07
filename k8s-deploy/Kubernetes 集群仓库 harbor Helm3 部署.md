# Kubernetes 集群仓库 harbor Helm3 部署

## 一、简介

Harbor 是一个用于存储和分发 Docker 镜像的企业级 Registry 服务器，通过添加一些企业必需的功能特性，例如安全、标识和管理等，扩展了开源 Docker Distribution。作为一个企业级私有 Registry 服务器，Harbor 提供了更好的性能和安全。提升用户使用 Registry 构建和运行环境传输镜像的效率。

## 二、先决条件

- Kubernetes 1.18
- Helm 3.4.2
- 集群有默认的动态存储可用
- 使用 StorageClass 提供 PV 动态存储

## 三、准备环境

### 1、系统环境

- kubernetes 版本：1.18.14
- Nginx Ingress 版本：latest
- Harbor Chart 版本：1.4.2
- Harbor 版本：2.0.2
- Helm 版本：3.4.2
- 持久化存储驱动：NFS

### 2、动态存储

```yaml
cat<< 'EOF' >sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: harbor-data-storage
provisioner: fuseim.pri/ifs
EOF
kubectl apply -f sc.yaml
```

查看StorageClass

```bash
[root@supper harbor]# kubectl get sc harbor-data-storage
NAME                  PROVISIONER      RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
harbor-data-storage   fuseim.pri/ifs   Delete          Immediate           false                  42s
```

### 3、安装 Helm3

#### 3.1、在线安装

Helm 现在具有一个安装程序脚本，该脚本将自动获取最新版本的 Helm 并将其本地安装。

#### 3.2、Helm下载安装(略)

### 4、创建 Namespace

```bash
kubectl create namespace harbor
```

## 四、创建自定义证书

安装 Harbor 我们会默认使用 HTTPS 协议，需要 TLS 证书，如果我们没用自己设定自定义证书文件，那么 Harbor 将自动创建证书文件，不过这个有效期只有一年时间，所以这里我们生成自签名证书，为了避免频繁修改证书，将证书有效期为 10 年，操作如下：

#### 1、生成CA证书私钥。

```sh
mkdir /root/harbor-ssl -p && cd /root/harbor-ssl
openssl genrsa -out ca.key 4096
```

#### 2、生成CA证书。

调整`-subj`选项中的值以反映您的组织。如果使用FQDN连接Harbor主机，则必须将其指定为通用名称（`CN`）属性。

```shell
openssl req -x509 -new -nodes -sha512 -days 3650 \
 -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=harbor.wzxmt.com" \
 -key ca.key \
 -out ca.crt
```

#### 3、生成服务器证书

证书通常包含一个`.crt`文件和一个`.key`文件，例如`yourdomain.com.crt`和`yourdomain.com.key`。

#### 4、生成私钥。

```shell
openssl genrsa -out tls.key 4096
```

#### 5、生成证书签名请求（CSR）。

调整`-subj`选项中的值以反映您的组织。如果使用FQDN连接Harbor主机，则必须将其指定为通用名称（`CN`）属性，并在密钥和CSR文件名中使用它。

```shell
openssl req -sha512 -new \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=harbor.wzxmt.com" \
    -key tls.key \
    -out tls.csr
```

#### 6、生成一个x509 v3扩展文件。

无论您使用FQDN还是IP地址连接到Harbor主机，都必须创建此文件，以便可以为您的Harbor主机生成符合主题备用名称（SAN）和x509 v3的证书扩展要求。替换`DNS`条目以反映您的域。

```shell
cat > v3.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1=harbor.wzxmt.com
DNS.2=wzxmt.com
DNS.3=harbor
EOF
```

#### 7、生成证书

使用该`v3.ext`文件为您的Harbor主机生成证书。

```shell
openssl x509 -req -sha512 -days 3650 \
    -extfile v3.ext \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -in tls.csr \
    -out tls.crt
```

#### 8、生成服务器证书

```bash
openssl x509 -inform PEM -in tls.crt -out tls.cert
```

#### 9、将服务器证书，密钥和CA文件Docker证书文件夹中

```bash
mkdir -p /etc/docker/certs.d/harbor.wzxmt.com:443
cp tls.cert ca.crt tls.key /etc/docker/certs.d/harbor.wzxmt.com:443
```

#### 10、生成 secret 对象

```yaml
cat << EOF >secret.yaml
apiVersion: v1
data:
  ca.crt: `cat ca.crt|base64 -w 0`
  tls.crt: `cat tls.crt|base64 -w 0`
  tls.key: `cat tls.key|base64 -w 0`
kind: Secret
metadata:
  name: registry-harbor-ingress
  namespace: harbor
  labels:
    app: harbor
    app.kubernetes.io/managed-by: Helm
    chart: harbor
    heritage: Helm
    release: registry
  annotations:
    meta.helm.sh/release-name: registry
    meta.helm.sh/release-namespace: harbor
type: kubernetes.io/dockerconfigjsonkubernetes.io/tls
EOF
kubectl apply -f secret.yaml
```

## 五、设置自定义参数

### 1、添加 Helm 仓库

```bash
helm repo add harbor https://helm.goharbor.io
```

### 2、下载Harbor

```bash
helm fetch harbor/harbor --untar
cd harbor
```

#### 3、修改values.yaml

```yaml
...
    hosts:
      ### 配置 Harbor 的访问域名，需要注意的是配置 notary 域名要和 core 处第一个单词外，其余保持一致
      core: harbor.wzxmt.com
      notary: notary.wzxmt.com
    controller: default
    annotations:
      ingress.kubernetes.io/ssl-redirect: "true"
      ingress.kubernetes.io/proxy-body-size: "0"
      #### 如果是 traefik ingress，则按下面配置：
      kubernetes.io/ingress.class: "traefik"
      traefik.ingress.kubernetes.io/router.tls: 'true'
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      #### 如果是 nginx ingress，则按下面配置：
      #nginx.ingress.kubernetes.io/ssl-redirect: "true"
      #nginx.ingress.kubernetes.io/proxy-body-size: "0"
      # 增加 Nignx配置，放开限制：A
      nginx.org/client-max-body-size: "0"
## 如果Harbor部署在代理后，将其设置为代理的URL，这个值一般要和上面的 Ingress 配置的地址保存一致
externalURL: https://harbor.wzxmt.com

### Harbor 各个组件的持久化配置，并设置各个组件 existingClaim 参数为上面创建的对应 PVC 名称
persistence:
  enabled: true
  ### 存储保留策略，当PVC、PV删除后，是否保留存储数据
  resourcePolicy: "keep"
  ### 修改storageClass: "harbor-data-storage"
...
      storageClass: "harbor-data-storage"
...
### 修改默认用户名admin密码
harborAdminPassword: "admin"
### 设置日志级别
logLevel: info
```

## 六、安装 Harbor

### 1、部署 Harbor

```bash
helm -n harbor install registry .
```

装完成后，我们核实下安装情况：

```bash
[root@supper ~]# k get pod -n harbor
NAME                                             READY   STATUS    RESTARTS   AGE
registry-harbor-chartmuseum-78b4dbdff6-hwqzp     1/1     Running   0          4m8s
registry-harbor-clair-74d46796c5-pqbjm           2/2     Running   5          4m7s
registry-harbor-core-54b4c64d77-6h8ww            1/1     Running   2          4m8s
registry-harbor-database-0                       1/1     Running   0          4m7s
registry-harbor-jobservice-7dd7d6cc58-2nvtf      1/1     Running   2          4m8s
registry-harbor-notary-server-6f9dd9c548-jspls   1/1     Running   3          4m7s
registry-harbor-notary-signer-6966978d45-rggxc   1/1     Running   4          4m8s
registry-harbor-portal-698df85d7f-fjf8p          1/1     Running   0          4m8s
registry-harbor-redis-0                          1/1     Running   0          4m7s
registry-harbor-registry-765d896bd-lc5ch         2/2     Running   0          4m8s
registry-harbor-trivy-0                          1/1     Running   0          4m7s
```

查看 ingress:

```bash
[root@supper ~]# kubectl get ingress -n harbor
NAME                             CLASS    HOSTS              ADDRESS   PORTS     AGE
registry-harbor-ingress          <none>   harbor.wzxmt.com             80, 443   4m32s
registry-harbor-ingress-notary   <none>   notary.wzxmt.com             80, 443   4m32s
```

### 2、Host 配置域名

接下来配置 Hosts，客户端想通过域名访问服务，必须要进行 DNS 解析，由于这里没有 DNS 服务器进行域名解析，所以修改 hosts 文件将 Harbor 指定节点的 IP 和自定义 host 绑定。

DNS解析

```bash
harbor	60 IN A 10.0.0.50
notary  60 IN A 10.0.0.50
```

### 3、访问 harbor

输入地址 [https://harbor.wzxmt.com](https://harbor.wzxmt.com) 访问 Harbor 仓库。

- 用户：admin
- 密码：admin (在安装配置中自定义的密码)
  ![访问 harbor](https://imgconvert.csdnimg.cn/aHR0cHM6Ly91cGxvYWRlci5zaGltby5pbS9mL0FBUllXbnJtWXNYSXpJbmoucG5nIXRodW1ibmFpbA?x-oss-process=image/format,png)

进入后可以看到 Harbor 的管理后台：
![管理后台](https://imgconvert.csdnimg.cn/aHR0cHM6Ly91cGxvYWRlci5zaGltby5pbS9mL1dwbWNtMVVDNTBnTGVPbkMucG5nIXRodW1ibmFpbA?x-oss-process=image/format,png)

### 5、服务器配置镜像仓库

#### 1、配置docker信任仓库地址

在etc/docker/daemon.json添加这两行

```bash
"insecure-registries": ["https://harbor.wzxmt.com"]
```

然后重启docker

```bash
systemctl restart docker.service
```

#### 2、登录 Harbor 仓库

```bash
docker login -u admin -p admin harbor.wzxmt.com
```

### 6、服务器配置 Helm Chart 仓库

#### 1、获取ca,私钥与公钥

```bash
kubectl get secrets -n harbor registry-harbor-ingress -o jsonpath="{.data.ca\.crt}"|base64 --decode >ca.crt
kubectl get secrets -n harbor registry-harbor-ingress -o jsonpath="{.data.tls\.crt}"|base64 --decode >tls.crt
kubectl get secrets -n harbor registry-harbor-ingress -o jsonpath="{.data.tls\.key}"|base64 --decode >tls.key
```

#### 2、配置 Helm 证书

跟配置 Docker 仓库一样，配置 Helm 仓库也得提前配置证书，上传 ca 签名到目录 `/etc/pki/ca-trust/source/anchors/`：

```bash
mkdir -p /etc/pki/ca-trust/source/anchors
cp ca.crt /etc/pki/ca-trust/source/anchors
```

> 如果下面执行的目录不存在，请用 yum 安装 ca-certificates 包。

执行更新命令，使证书生效:

```bash
update-ca-trust extract 
```

#### 3、添加 Helm 仓库

添加 Helm 仓库:

```bash
helm repo add myrepo --ca-file=ca.crt --cert-file=tls.crt --key-file=tls.key --username=admin --password=admin https://harbor.wzxmt.com/chartrepo
```

- `-username`：harbor仓库用户名
- `-password`：harbor仓库密码
- `-ca-file`：指向ca.crt证书地址
- `chartrepo`：如果是chart仓库地址，中间必须加 chartrepo
- `library`：仓库的项目名称

查看仓库列表：

```bash
$ helm repo list

NAME            URL                                                                                  
myrepo          https://harbor.wzxmt.com/chartrepo/library 
```

## 七、测试功能

### 1、推送与拉取 Docker 镜像

这里为了测试推送镜像，先下载一个用于测试的 helloworld 小镜像，然后推送到 hub.mydlq.club 仓库：

```bash
# 拉取 Helloworld 镜像
docker pull hello-world:latest

# 将下载的镜像使用 tag 命令改变镜像名
docker tag hello-world:latest harbor.wzxmt.com/library/hello-world:latest

# 推送镜像到镜像仓库
docker push harbor.wzxmt.com/library/hello-world:latest
```

将之前的下载的镜像删除，然后测试从 `harbor.wzxmt.com` 下载镜像进行测试：

```bash
# 删除之前镜像
docker rmi hello-world:latest
docker rmi hello-world:latest harbor.wzxmt.com/library/hello-world:latest

# 测试从 `harbor.wzxmt.com` 下载新镜像
docker pull harbor.wzxmt.com/library/hello-world:latest
```

### 2、推送与拉取 Chart

Helm 要想推送 Chart 到 Helm 仓库，需要提前安装上传插件：

```bash
helm plugin install https://github.com/chartmuseum/helm-push

# 然后创建一个测试的 Chart 进行推送测试：
helm create hello

# 打包chart，将chart打包成tgz格式
helm package hello

# 推送 chart 进行测试
helm push hello-0.1.0.tgz myrepo

#下载 chart 进行测试
helm fetch myrepo/library/hello --untar
```

## 八、遇到的问题

### 1、Error response from daemon: Get https://harbor.wzxmt.com/v2/: x509: certificate signed by unknown authorit

需要到 `docker.service` 中修改下参数就可以了

修改 `/usr/lib/systemd/system/docker.service` 配置：

```bash
# ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecStart=/usr/bin/dockerd -H tcp://0.0.0.0:2375 -H unix://var/run/docker.sock
```

重启docker：

```bash
## 守护进程重启
systemctl daemon-reload
## 重启docker服务
systemctl restart docker
```

### 2、413 Request Entity Too Large

```bash
[root@supper ~]# docker push harbor.wzxmt.com/infra/myapp:v2
The push refers to repository [harbor.wzxmt.com/infra/myapp]
05a9e65e2d53: Layer already exists
68695a6cfd7d: Layer already exists
c1dc81a64903: Layer already exists
8460a579ab63: Pushing [==================================================>]  11.51MB/11.51MB
d39d92664027: Pushing [==================================================>]  3.991MB/3.991MB
error parsing HTTP 413 response body: invalid character '<' looking for beginning of value: "<html>\r\n<head><title>413 Request Entitarge</h1></center>\r\n<hr><center>nginx/1.18.0</center>\r\n</body>\r\n</html>\r\n"
```

解决办法是自定义参数文件增加：

```yaml
  ingress:
    hosts:
      ### 配置 Harbor 的访问域名，需要注意的是配置 notary 域名要和 core 处第一个单词外，其余保持一致
      core: harbor.wzxmt.com
      notary: notary.wzxmt.com
    controller: default
    annotations:
      ingress.kubernetes.io/ssl-redirect: "true"
      ingress.kubernetes.io/proxy-body-size: "0"
      #### 如果是 traefik ingress，则按下面配置：
#      kubernetes.io/ingress.class: "traefik"
#      traefik.ingress.kubernetes.io/router.tls: 'true'
#      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      #### 如果是 nginx ingress，则按下面配置：
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/proxy-body-size: "0"
      # 增加 Nignx配置，放开限制：A
      nginx.org/client-max-body-size: "0"
```

如果使用nginx代理转发traefik，需要在nginx上修改上传大小限制

```nginx
#nginx 默认的request body为1M
client_max_body_size 1024m;
```
