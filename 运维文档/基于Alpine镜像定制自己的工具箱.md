# Alpine介绍

Alpine Linux是体积最小的Linux发行版，它重点关注于安全和速度。使用apk能够很快地安装软件包，默认情况下，镜像只包含了完成基础UNIX任务所需要的东西 ，因此相对于其它Docker基础镜像，体积会更小。

Alpine的特点：

- 小巧：基于Musl libc和busybox，和busybox一样小巧，最小的Docker镜像只有5MB；
- 安全：面向安全的轻量发行版；
- 简单：提供APK包管理工具，软件的搜索、安装、删除、升级都非常方便。
- 适合容器使用：由于小巧、功能完备，非常适合作为容器的基础镜像。

```bash
# 拉取镜像
docker pull alpine
# 查看镜像大小
docker images | grep alpine
# 运行镜像
docker run -it alpine:latest
```

# Alpine软件包管理

### **1、 配置软件源**

Alpine源配置文件

```bash
/ # cat /etc/apk/repositories
https://dl-cdn.alpinelinux.org/alpine/v3.14/main
https://dl-cdn.alpinelinux.org/alpine/v3.14/community
```

由于种种原因，官方源在国内很慢，甚至无法连接，我们将其改为国内镜像源

```bash
/ # cat /etc/apk/repositories
https://mirrors.ustc.edu.cn/alpine/v3.14/main
https://mirrors.ustc.edu.cn/alpine/v3.14/community
```

### **2、 软件包管理**

alpine 提供了非常好用的apk软件包管理工具，可以方便地安装、删除、更新软件。

**更新最新镜像源列表**

```
apk update 
```

**查询软件**

```bash
apk search #查找所以可用软件包
apk search -v #查找所以可用软件包及其描述内容
apk search -v 'acf*' #通过软件包名称查找软件包
apk search -v -d 'docker' #通过描述文件查找特定的软件包
```

**安装软件**

```bash
apk add openssh #安装一个软件
apk add openssh openntp vim   #安装多个软件
apk add --no-cache mysql-client  #不使用本地镜像源缓存，相当于先执行update，再执行add
```

**列出已安装的软件包**

```bash
apk info #列出所有已安装的软件包
apk info -a zlib #显示完整的软件包信息
apk info --who-owns /sbin/lbu #显示指定文件属于的包
```

**升级软件版本**

```bash
apk upgrade #升级所有软件
apk upgrade openssh #升级指定软件
apk upgrade openssh openntp vim   #升级多个软件
apk add --upgrade busybox #指定升级部分软件包
```

**卸载软件**

```bash
apk del openssh  #删除一个软件
```

# alpine linux 安装包报错

### 1、apk search curl 时候报错

```bash
/ # apk search curl
WARNING: Ignoring https://mirrors.ustc.edu.cn/alpine/v3.14/main: No such file or directory
WARNING: Ignoring https://mirrors.ustc.edu.cn/alpine/v3.14/community: No such file or directory
```

解决办法

```bash
apk update
```

### 2、时间相差8小时

```bash
apk add -U tzdata && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && apk del tzdata
```

# 构建工具箱

**Dockerfile**

```bash
cat << 'EOF' >Dockerfile
FROM alpine:latest
    #修改源
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories && \
    apk update && apk upgrade && \
    #修改时间
    apk add -U tzdata && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && apk del tzdata && \
    #添加telnet、curl、nslookup、scp
    apk add curl && apk add net-tools && apk add busybox-extras && apk add openssh-client && \
    #添加redis、mysql、mongo
    apk add --no-cache mysql-client && apk add --no-cache redis && apk add mongodb-tools && \
    echo '*/1 * * * * /bin/echo 1 >>/root/1.txt' >var/spool/cron/crontabs/root && \ 
    rm -rf /var/cache/apk/* 
CMD ["crond","&&","tail","-f","/dev/null" ]
EOF
```

**构建**

```bash
docker build -t tools:latest .
```

### **使用alpine构建镜像**

1、dockerhub上的例子

```bash
FROM alpine:3.7
RUN apk add --no-cache mysql-client
ENTRYPOINT ["mysql"]
```

2、构建一个nginx镜像

```bash
FROM alpine:3.3
MAINTAINER Marin "1164216442@qq.com.cn"
 
EXPOSE 80 443
CMD ["nginx", "-g", "daemon off;"]
VOLUME ["/var/cache/nginx"]
 
RUN  sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories \ 
  && echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \ 
  && apk update \
  && apk add nginx \
#  && build_pkgs="build-base linux-headers openssl-dev pcre-dev wget zlib-dev openssl pcre zlib" \
#  && apk --update add ${build_pkgs} \
#  && cd /tmp \
#  && wget http://nginx.org/download/nginx-1.16.1.tar.gz \
#  && tar xzf nginx-1.16.1.tar.gz \
#  && cd /tmp/nginx-1.16.1 \
#  && ./configure \
#    --prefix=/etc/nginx \
#    --sbin-path=/usr/sbin/nginx \
#    --conf-path=/etc/nginx/nginx.conf \
#    --error-log-path=/var/log/nginx/error.log \
#    --http-log-path=/var/log/nginx/access.log \
#    --pid-path=/var/run/nginx.pid \
#    --lock-path=/var/run/nginx.lock \
#    --http-client-body-temp-path=/var/cache/nginx/client_temp \
#    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
#    --http-fascgi-temp-path=/var/cache/nginx/fascgi_temp \
#    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
#    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
#    --user=nginx \
#    --group=nginx \
#    --with-http_ssl_module \
#    --with-http_realip_module \
#    --with-http_addition_module \
#    --with-http_sub_module \
#    --with-http_dav_module \
#    --with-http_flv_module \
#    --with-http_mp4_module \
#    --with-http_gunzip_module \
#    --with-http_gzip_static_module \
#    --with-http_random_index_module \
#    --with-http_secure_link_module \
#    --with-http_stub_status_module \
#    --with-http_auth_request_module \
#    --with-threads \
#    --with-stream \
#    --with-stream_ssl_module \
#    --with-http_slice_module \
#    --with-mail \
#    --with-mail_ssl_module \
#    --with-file-aio \
#    --with-http_v2_module \
#&& make \
#&& make install \
#&& sed -i -e 's/#access_log  logs\/access.log  main;/access_log  \/dev\/stdout;/' -e 's/#error_log  logs\/error.log  notice;/error_log stderr notice;/' /etc/nginx/nginx.conf \
&& rm -rf /tmp/* \
&& apk del ${build_pkgs} \
rm -rf /var/cache/apk/*
```

注："nginx", "-g", "daemon off;"

在容器里nginx是以daemon方式启动，退出容器时，nginx程序也会随着停止
/usr/local/nginx/sbin/nginx 使用前台方式永久运行: /usr/local/nginx/sbin/nginx -g "daemon off;"

### **多阶段构建，go应用容器化打包示例**

基础镜像 golang:1.16.2-alpine比golang:1.16.2小500M左右

```bash

# 构建阶段 build stage
FROM golang:stretch AS build-env
ADD . /go/src
WORKDIR /go/src
 
ENV GO111MODULE=on
ENV APP_NAME="goappname"
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -mod=vendor -o ${APP_NAME}
RUN pwd && ls -lsa
# 构建物打包阶段 final stage
FROM alpine:latest
## 配置 apk包加速镜像为阿里
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
## 安装 一些基础包
RUN apk update \
    && apk upgrade \
    #&& apk add s6 \
    && apk add bash \
    #&& apk add nghttp2-dev \
    && apk add ca-certificates \
    && apk add wget \
    #&& apk add curl \
    #&& apk add tcpdump \
    && apk add iputils \
    && apk add iproute2 \
    && apk add libc6-compat \
    && apk add -U tzdata \
    && rm -rf /var/cache/apk/*
# 设置 操作系统时区
RUN rm -rf /etc/localtime \
 && ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
# 打包 应用
ENV APP_NAME="goappname"
ENV APP_ROOT="/data/apps/"${APP_NAME}
RUN mkdir -p $APP_ROOT
WORKDIR $APP_ROOT
# 从构建阶段复制构建物
COPY --from=build-env /go/src/${APP_NAME}  $APP_ROOT/
# 增加 配置文件、其他依赖文件
COPY config/config.toml.tpl $APP_ROOT/config/
RUN  ls -lsah && pwd && mv ./config/config.toml.tpl ./config/config.toml && ls -lsah  $APP_ROOT/config && cat config/config.toml
# 配置 对外端口
EXPOSE 10000
# 设置启动时预期的命令参数, 可以被 docker run 的参数覆盖掉.
CMD $APP_ROOT/$APP_NAME
```

### **Python应用容器化打包示例**

```bash
FROM alpine:latest
# 打标签
LABEL version="1.0" \
    description="alpine:latest" \
    maintainer="wwek<licoolgo@gmail.com>"
# 配置apk包加速镜像为阿里
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
# 安装一些基础包
RUN apk update \
    && apk upgrade \
    && apk add s6 \
    && apk add bash \
    # && apk add nghttp2-dev \
    && apk add ca-certificates \
    && apk add wget \
    # && apk add curl \
    # && apk add tcpdump \
    # && apk add bash-completion \
    && apk add iputils \
    && apk add iproute2 \
    && apk add libc6-compat \
    && apk add -U tzdata \
    && rm -rf /var/cache/apk/*
# 设置 操作系统时区
RUN rm -rf /etc/localtime \
 && ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
# 设置时区变量
ENV TIME_ZONE Asia/Shanghai
# 安装 python3、升级pip、setuptools
RUN apk add --no-cache python3 \
    #&& apk add --no-cache python3-dev \
    && python3 -m ensurepip \
    && rm -r /usr/lib/python*/ensurepip \
    && pip3 install --default-timeout=100 --no-cache-dir --upgrade pip \
    && pip3 install --default-timeout=100 --no-cache-dir --upgrade setuptools \
    && if [ ! -e /usr/bin/pip ]; then ln -s pip3 /usr/bin/pip ; fi \
    && if [[ ! -e /usr/bin/python ]]; then ln -sf /usr/bin/python3 /usr/bin/python; fi \
    && rm -rf /var/cache/apk/* \
    && rm -rf ~/.cache/pip
# 设置 语言支持
ENV LANG=C.UTF-8
# 配置 应用工作目录
WORKDIR /data/apps/appdir
# 增加 项目文件
ADD appmain.py ./
ADD 你的py文件2.py ./
ADD 目录1 ./
ADD requirements.txt ./
# 安装 项目依赖包
RUN pip install -r requirements.txt
# 配置 对外端口
EXPOSE 11000
# 设置启动时预期的命令参数, 可以被 docker run 的参数覆盖掉.
CMD ["python", "appmain.py"]
```

支持HTTP2的curl：

```bash
cat << 'EOF' >Dockerfile
FROM alpine:latest
RUN echo https://dl-cdn.alpinelinux.org/alpine/edge/testing >>/etc/apk/repositories 
ENV CURL_VERSION 7.50.1
RUN apk add --update --no-cache openssl openssl-dev nghttp2-dev ca-certificates
RUN apk add --update --no-cache --virtual curldeps g++ make perl && \
wget https://curl.haxx.se/download/curl-$CURL_VERSION.tar.bz2 && \
tar xjvf curl-$CURL_VERSION.tar.bz2 && \
rm curl-$CURL_VERSION.tar.bz2 && \
cd curl-$CURL_VERSION && \
./configure \
    --with-nghttp2=/usr \
    --prefix=/usr \
    --with-ssl \
    --enable-ipv6 \
    --enable-unix-sockets \
    --without-libidn \
    --disable-static \
    --disable-ldap \
    --with-pic && \
make && \
make install && \
cd / && \
rm -r curl-$CURL_VERSION && \
rm -r /var/cache/apk && \
rm -r /usr/share/man && \
apk del curldeps
CMD ["curl"]
EOF
```

构建并且运行镜像

```bash
docker build -t curl:latest .
```

测试

```bash
docker run curl:latest curl -s --http2 -I https://nghttp2.org
```

k8s运行

```bash
kubectl run curl -it --rm --image=curl:latest --image-pull-policy=IfNotPresent -- curl -s --http2 -I https://nghttp2.org
```

