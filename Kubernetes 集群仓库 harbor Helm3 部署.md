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

#### 3、将生成的tls.crt与tls.key替换cert下的证书

```bash
\cp /root/harbor-ssl/* cert/
```

#### 4、修改values.yaml

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

部署 Harbor

```bash
helm -n harbor install harbor .
```

装完成后，我们核实下安装情况：

```bash
[root@supper harbor]# k get pod -n harbor
NAME                                           READY   STATUS    RESTARTS   AGE
harbor-harbor-chartmuseum-54dcdffc65-psqfl     1/1     Running   0          6m31s
harbor-harbor-clair-55dccb7ff-txds5            2/2     Running   0          6m31s
harbor-harbor-core-5847df9656-sqgpv            1/1     Running   3          6m31s
harbor-harbor-database-0                       1/1     Running   0          6m31s
harbor-harbor-jobservice-58cfc7df5b-vx8zq      1/1     Running   3          6m31s
harbor-harbor-notary-server-c5867b899-ckdg9    1/1     Running   5          6m31s
harbor-harbor-notary-signer-5899b7f9f6-s4x68   1/1     Running   5          6m31s
harbor-harbor-portal-6667868cb5-5ln55          1/1     Running   0          6m31s
harbor-harbor-redis-0                          1/1     Running   0          6m31s
harbor-harbor-registry-6894b57978-d9m7x        2/2     Running   0          6m31s
harbor-harbor-trivy-0                          1/1     Running   0          6m31s
```

查看 ingress:

```bash
[root@supper harbor]#  kubectl get ingressroute -n harbor
NAME                           AGE
harbor-harbor-ingress          3m36s
harbor-harbor-ingress-notary   14m
```

### 3、Host 配置域名

接下来配置 Hosts，客户端想通过域名访问服务，必须要进行 DNS 解析，由于这里没有 DNS 服务器进行域名解析，所以修改 hosts 文件将 Harbor 指定节点的 IP 和自定义 host 绑定。

DNS解析

```bash
harbor	60 IN A 10.0.0.50
notary  60 IN A 10.0.0.50
```

### 4、访问 harbor

输入地址 [https://harbor.wzxmt.com](https://harbor.wzxmt.com) 访问 Harbor 仓库。

- 用户：admin
- 密码：admin (在安装配置中自定义的密码)
  ![访问 harbor](https://imgconvert.csdnimg.cn/aHR0cHM6Ly91cGxvYWRlci5zaGltby5pbS9mL0FBUllXbnJtWXNYSXpJbmoucG5nIXRodW1ibmFpbA?x-oss-process=image/format,png)

进入后可以看到 Harbor 的管理后台：
![管理后台](https://imgconvert.csdnimg.cn/aHR0cHM6Ly91cGxvYWRlci5zaGltby5pbS9mL1dwbWNtMVVDNTBnTGVPbkMucG5nIXRodW1ibmFpbA?x-oss-process=image/format,png)

### 5、服务器配置镜像仓库

#### 1、下载 Harbor 证书

由于 Harbor 是基于 Https 的，故而需要提前配置 tls 证书，进入：Harobr主页->配置管理->系统配置->镜像库根证书
![下载 Harbor 证书](https://img-blog.csdnimg.cn/20200827155332448.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L3p1b3pld2Vp,size_16,color_FFFFFF,t_70#pic_center)

#### 2、服务器 Docker 中配置 Harbor 证书

然后进入服务器，在服务器上 `/etc/docker` 目录下创建 certs.d 文件夹，然后在 certs.d 文件夹下创建 Harobr 域名文件夹，可以输入下面命令创建对应文件夹：

```bash
mkdir -p /etc/docker/certs.d/harbor
```

然后再 /etc/docker/certs.d/hub.mydlq.club 目录下上床上面的 ca 证书文件。

#### 3、登录 Harbor 仓库

只有登录成功后才能将镜像推送到镜像仓库，所以配置完证书后尝试登录，测试是否能够登录成功：

如果提示 ca 证书错误，则重建检测证书配置是否有误。

```bash
docker login -u admin -p admin harbor.wzxmt.com
```

### 6、服务器配置 Helm Chart 仓库

#### 1、配置 Helm 证书

跟配置 Docker 仓库一样，配置 Helm 仓库也得提前配置证书，上传 ca 签名到目录 `/etc/pki/ca-trust/source/anchors/`：

```bash
$ cat /etc/pki/ca-trust/source/anchors/ca.crt
-----BEGIN CERTIFICATE-----
MIIC9TCCAd2gAwIBAgIRALztT/b8wlhjw50UECEOTR8wDQYJKoZIhvcNAQELBQAw
FDESMBAGA1UEAxMJaGFyYm9yLWNhMB4XDTIwMDIxOTA3NTgwMFoXDTIxMDIxODA3
NTgwMFowFDESMBAGA1UEAxMJaGFyYm9yLWNhMIIBIjANBgkqhkiG9w0BAQEFAAOC
AQ8AMIIBCgKCAQEArYbsxYmNksU5eQhVIM3OKac4l6MV/5u5belAlWSdpbbQCwMF
G/gAliTSQMgqcmhQ3odYTKImvx+5zrhP5b1CWXCQCVOlOFSLrs3ZLv68ZpKoDLkg
6XhoQFVPLM0v5V+YzWCGAson81LfX3tDhltnOItSpe2KESABVH+5L/2vo25P7Mvw
4bWEWMyY4AS/3toiDZjhwNMrMb2lpICrlH9Sc3dAOzUteyVznA5/WF8IyPI64aKn
tl0gxLOZgUBTkBoxVhPj7dNNZu8lMnqAYXmhWt+oRr7t1HHp2lOtk2u/ndyV0kKL
xufx5FYVJQel2yRBGc/C1QLN18nC1y6u5pITaQIDAQABo0IwQDAOBgNVHQ8BAf8E
BAMCAqQwHQYDVR0lBBYwFAYIKwYBBQUHAwEGCCsGAQUFBwMCMA8GA1UdEwEB/wQF
MAMBAf8wDQYJKoZIhvcNAQELBQADggEBACFT92PWBFeCT7By8y8+EkB2TD1QVMZm
NDpBS75q5s2yIumFwJrbY6YsHtRkN1Zx9jc4LiJFHC6r0ES3tbCDapsxocvzn7dW
XLNTtnSx0zPxNXZzgmTsamfunBd4gszdXMshJ+bKsEoTXhJEXVjZq/k0EZS8L4Mp
NZ7ciPqwAI1Tg+mFGp5UOvzxYLyW8nCLPykC73y3ob1tiO6xdyD/orTAbA6pIMc9
7ajTfwYj4Q6JPY/QAmu0S+4hJHs724IrC6hiXUlQNVVRW/d3k+nXbYttnnmPnQXC
RyK2ru7R8H43Zlwj26kQJo6naQoQ0+Xcjcyk5llPqJxCrk3uoHF0r4U=
-----END CERTIFICATE-----
```

> 如果下面执行的目录不存在，请用 yum 安装 ca-certificates 包。

执行更新命令，使证书生效:

```bash
update-ca-trust extract 
```

#### 2、添加 Helm 仓库

添加 Helm 仓库:

```bash
helm repo add myrepo --username=admin --password=admin@123 https://hub.7d.com/chartrepo/library
1
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
myrepo          https://hub.7d.com/chartrepo/library 
1234
```

## 七、测试功能

### 1、推送与拉取 Docker 镜像

这里为了测试推送镜像，先下载一个用于测试的 helloworld 小镜像，然后推送到 hub.mydlq.club 仓库：

```bash
# 拉取 Helloworld 镜像
docker pull hello-world:latest

# 将下载的镜像使用 tag 命令改变镜像名
docker tag hello-world:latest hub.7d.com/library/hello-world:latest

# 推送镜像到镜像仓库
docker push hub.7d.com/library/hello-world:latest
12345678
```

将之前的下载的镜像删除，然后测试从 `hub.7d.com` 下载镜像进行测试：

```bash
# 删除之前镜像
docker rmi hello-world:latest
docker rmi hello-world:latest hub.7d.com/library/hello-world:latest

# 测试从 `hub.7d.com` 下载新镜像
docker pull hub.7d.com/library/hello-world:latest
123456
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

Pushing hello-0.1.0.tgz to myrepo...
123456789101112
```

## 八、遇到的问题

### 1、Error response from daemon: Get https://hub.7d.com/v2/: x509: certificate signed by unknown authorit

需要到 `docker.service` 中修改下参数就可以了

修改 `/usr/lib/systemd/system/docker.service` 配置：

```bash
# ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecStart=/usr/bin/dockerd -H tcp://0.0.0.0:2375 -H unix://var/run/docker.sock
12
```

重启docker：

```bash
## 守护进程重启
sudo systemctl daemon-reload

## 重启docker服务
sudo systemctl restart docker
12345
```

### 2、413 Request Entity Too Large

```bash
$ docker push hub.7d.com/mall_repo/mall-portal:1.0
The push refers to repository [hub.7d.com/mall_repo/mall-portal]
5a8f64cc7f4c: Pushing [==================================================>]  73.98MB/73.98MB
35c20f26d188: Layer already exists 
c3fe59dd9556: Preparing 
6ed1a81ba5b6: Layer already exists 
a3483ce177ce: Layer already exists 
ce6c8756685b: Waiting 
30339f20ced0: Waiting 
0eb22bfb707d: Waiting 
a2ae92ffcd29: Waiting 
error parsing HTTP 413 response body: invalid character '<' looking for beginning of value: "<html>\r\n<head><title>413 Request Entity Too Large</title></head>\r\n<body>\r\n<center><h1>413 Request Entity Too Large</h1></center>\r\n<hr><center>nginx/1.17.3</center>\r\n</body>\r\n</html>\r\n"
123456789101112
```

解决办法是自定义参数文件增加：

```yaml
  ingress:
    hosts:
      ### 配置 Harbor 的访问域名，需要注意的是配置 notary 域名要和 core 处第一个单词外，其余保持一致
      core: hub.7d.com
      notary: notary.7d.com
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
123456789101112131415161718
```

示例源码：

- https://github.com/zuozewei/blog-example/tree/master/Kubernetes/k8s-harbor