## Docker Registry简介

Docker Registry是开源的软件，可以进行存储和分发Docker镜像。Docker Registry包括两个关键组成部分：[Docker Trusted Registry](https://link.segmentfault.com/?enc=X%2BRTYkIFXJQkFe8s2lRIcQ%3D%3D.mpU%2FHWzBcarjmfJrZjhvND6ez7ZuzXzmRwULCBzZ7XIT2pglQg%2FwwN%2BcUpioUvO91kqDEKB2KwiIzk%2F1vWVoMg%3D%3D)和[Docker Hub](https://link.segmentfault.com/?enc=I1WxNR02jPkUHgOd3b%2FNwg%3D%3D.A5vx3EUjXH0br0ULRdJk8c9mFWxvOJFTju6tdxMdxJZEwnVJ%2BsgKu9Upyi6WWwLH)。简单理解，第一个是负责存储的，第二个是负责管理镜像。

### 配置私有仓库

```json
mkdir -p /etc/docker
vi /etc/docker/daemon.json
{  
	"registry-mirrors": ["http://hub-mirror.c.163.com"],
	"insecure-registries":["xxx.xxx.xxx.xxx"] 
}
```

### 运行Docker Registry

```bash
docker run -d -p 443:5000 --restart=always --name registryregistry:latest
```

测试推送：

```bash
docker pull busybox 
docker tag busybox localhost/busybox
docker push localhost/busybox
```

测试拉取

```nginx
docker pull localhost/busybox
```

### 镜像文件存储本地

```bash
docker run -d -p 443:5000 --restart=always --name registry \
  -v `pwd`/data:/var/lib/registry \
 registry:latest
```

### 使用https

新建conf目录，将证书拷贝到目录里面：

```bash
docker run -d -p 443:5000 --restart=always --name registry \
  -v `pwd`/conf:/conf \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/conf/domain.pem \
  -e REGISTRY_HTTP_TLS_KEY=/conf/domain.key \
  registry:latest
```

测试推送、拉取同上

### 添加权限认证

按照之前的步骤，任何人都可以push和pull这个仓库中的镜像。如果443端口暴露在外网中，最好加个权限认证。

`testuser`和`testpassword`分别为用户名和密码：

安装

```bash
 yum install -y  httpd-tools
```

生成文件

```bash
mkdir -p conf
htpasswd -Bbn bridge5 BridgeAmss2021 > conf/htpasswd
```

然后再执行启动命令：

```bash
docker run -d -p 443:5000 --restart=always --name registry \
  -v `pwd`/conf:/conf \
  -e "REGISTRY_AUTH=htpasswd" \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/conf/htpasswd \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/conf/domain.pem \
  -e REGISTRY_HTTP_TLS_KEY=/conf/domain.key \
  registry:latest
```

这样，访问registry就需要先login，`docker login myregistrydomain.com`，按提示输入用户名和密码即可。

------

### 使用阿里云的OSS保存镜像文件

默认镜像文件存到本地磁盘，这个可扩展性不是很好，官方registry中已经包含OSS的驱动，我们可以把镜像文件存到OSS中。

docker方式

```bash
docker run -d -p 443:5000 --restart=always --name registry \
  -v `pwd`/conf:/conf \
  -e "REGISTRY_AUTH=htpasswd" \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/conf/htpasswd \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/conf/domain.pem \
  -e REGISTRY_HTTP_TLS_KEY=/conf/domain.key \
  -e REGISTRY_STORAGE=oss \
  -e REGISTRY_STORAGE_OSS_ACCESSKEYID=********** \
  -e REGISTRY_STORAGE_OSS_ACCESSKEYSECRET=***************** \
  -e REGISTRY_STORAGE_OSS_REGION=oss-cn-qingdao \
  -e REGISTRY_STORAGE_OSS_BUCKET=******* \
  registry:latest
```

docker-compose

```yaml
mkdir -p docker-registry && cd docker-registry
cat << 'EOF' >docker-compose.yml
version: '3.9'
services:
  registry:
    restart: always
    image: registry:latest
    container_name: amss-registry
    ports:
      - 5000:5000
    volumes:
      - ./conf:/conf
    environment:
      - REGISTRY_AUTH=htpasswd
      - REGISTRY_AUTH_HTPASSWD_REALM=Registry_Realm
      - REGISTRY_AUTH_HTPASSWD_PATH=/conf/htpasswd
      - REGISTRY_HTTP_TLS_CERTIFICATE=/conf/amssasia.com.cn.pem
      - REGISTRY_HTTP_TLS_KEY=/conf/amssasia.com.cn.key
      - REGISTRY_STORAGE=oss
      - REGISTRY_STORAGE_OSS_ACCESSKEYID=LTAI4GCqHJUFpuuDJRN2tweb
      - REGISTRY_STORAGE_OSS_ACCESSKEYSECRET=9aQ0ss8PhT7oecT9N3wnVz0gfUOYQP
      - REGISTRY_STORAGE_OSS_REGION=oss-cn-shanghai
      - REGISTRY_STORAGE_OSS_BUCKET=amss-registry
    networks:
      - registry-networks
    restart: always

networks:
  registry-networks:
    name: registry-networks
EOF
```

参数详解：

REGISTRY_STORAGE=oss #存储方式
REGISTRY_STORAGE_OSS_ACCESSKEYID= #添写id
REGISTRY_STORAGE_OSS_ACCESSKEYSECRET= #secret
REGISTRY_STORAGE_OSS_REGION=cn-oss-xxxxx #说明区域，北京就是cn-oss-beijing
REGISTRY_STORAGE_OSS_BUCKET=buket_name #刚刚新建的buket

打标签及上传镜像

```
docker login https://registry.amssasia.com.cn

docker tag busybox:latest registry.amssasia.com.cn/busybox:latest    

docker push registry.amssasia.com.cn/busybox:latest  
```

查询镜像

```
curl -u bridge5:BridgeAmss2021 -X GET https://registry.amssasia.com.cn/v2/_catalog
```