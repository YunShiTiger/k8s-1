## curl命令的最小镜像

Dockerfile如下

```dockerfile
FROM alpine:latest
RUN apk add --update curl && rm -rf /var/cache/apk/*
```

在 Alpine Linux 的 docker 镜像中安装 curl 时下载速度很慢，请问如何解决？

```dockerfile
Step 2/2 : RUN apk update && apk add curl && rm -rf /var/cache/apk/*
 ---> Running in 86c4e9f3daca
fetch http://dl-cdn.alpinelinux.org/alpine/v3.10/main/x86_64/APKINDEX.tar.gz
```

 将 alpine linux apk 的安装源改为国内镜像可解决

```dockerfile
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
```

调整后的Dockerfile如下

```dockerfile
FROM alpine
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
RUN apk add --update curl && rm -rf /var/cache/apk/*
```

## 支持HTTP2的CURL最小化Docker镜像

这就是支持HTTP2的curl的Dockerfile：

```dockerfile
FROM alpine:edge
# For nghttp2-dev, we need this respository.
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
```

详细的构建步骤,让我们更深入地了解Dockerfile。

```dockerfile
FROM alpine:edge
# For nghttp2-dev, we need this respository.
RUN echo https://dl-cdn.alpinelinux.org/alpine/edge/testing >>/etc/apk/repositories 
```

在Alpine的edge分支中，nghttp2包（支持cURL中的HTTP2所必需的包）只有在testing仓库有效，因此这几行命令确保了当我们执行apk install时nghttp2包能够被正确安装。阅读“如何让cURL支持HTTP2”的文档就会发现， nghttp2库是必需的（由于HTTP2所带来的复杂性），并且在Alpine的归档中闲逛时，发现了edge分支中nghttp2只在testing仓库有效。

```dockerfile
ENV CURL_VERSION 7.50.1
```

当cURL发布了新版本，我们想要更新镜像，我们仅仅需要修改这个文件的一处位置——环境变量，7.50.1表示在写作时cURL最新的稳定版。

```dockerfile
RUN apk add --update --no-cache openssl openssl-dev nghttp2-dev ca-certificates
```

这些是我们想要最终保留在镜像的依赖，默认证书和库是为了让curl支持SSL（HTTPS连接）。注意—no-cache，这个确保了apk不会使用多余的硬盘空间来缓存包位置查找的结果，最终就会节省镜像的空间。

下一条RUN命令只会产生一个文件层（因此我们可以安装一些依赖，使用它们，然后清除它们，不将它们保留在最终镜像中）。这条命令内容比较多，让我们一步一步来看它们到底做了什么操作。

```dockerfile
RUN apk add --update --no-cache --virtual curldeps g++ make perl && \
```

以上全都是成功编译和安装curl所需要的工具。--virtual是一个非常有用的apk特性——虚拟包。你可以给予包的集合一个标签，然后通过使用一条命令 apk del virtual-pkg-name来将它们全部清除。

```dockerfile
wget https://curl.haxx.se/download/curl-$CURL_VERSION.tar.bz2 && \
tar xjvf curl-$CURL_VERSION.tar.bz2 && \
rm curl-$CURL_VERSION.tar.bz2 && \
cd curl-$CURL_VERSION && \
```

获得cURL的源码压缩包，解压它，删除压缩包（我们在解压后就不需要它了），然后使用cd命令进入到源文件目录。

```bash
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
```

在熟悉的./configure;make;make install命令的基础上加上了一些cURL特有的偏好设置。--with-nghttp2=/usr就是用来配置HTTP2支持的，由于我们将nghttp2-dev安装在Aline的/usr/lib目录下，在构建cURL的时候，程序会自动在/usr下的lib目录寻找一个包配置文件。因此，你可能在其他的例子中看到参数设置为/usr/local或者其它目录。

大多数的其它参数（除了—with-ssl）都是都拷贝自上游对curl包的请输入链接描述APKBUILD文件。由于Alpine的包维护者比较可靠，因此我决定复用这些已经存在的配置。如果我对这么做感到太鲁莽，那么我将会深入进去，然后从底层的角度来决定哪些我需要，哪些不需要，但是我还是希望它们包含UNIX套接字和IPV6的支持，因此我保留了这些已存在的配置。

```bash
cd / && \
rm -r curl-$CURL_VERSION && \
rm -r /var/cache/apk && \
rm -r /usr/share/man && \
apk del curldeps
```

以上全都是清除工作。

保留构建目录（也就是二进制文件被安装的地方），去除源代码目录，运行apk del curldepsenter code here命令来清除我们之前创建的虚拟包，接下来再去除/var/cache/apk（这是包缓存，老实说，我也不清楚为什么使用了—no-cache选项，缓存依旧存在）和/usr/share/man目录（帮助手册，在man命令没有被安装的情况下，这是无用的）。其中一些清除操作，尤其是缓存和帮助页面的清除，某种程度上可以说是对缩小镜像体积的一种怪癖，毕竟它们实际上不会超过1MB。这些都是我通过运行du | sort -n后，认为在最终镜像中可能不必要的内容，我只能说，我狂热地追求尽可能地缩小镜像体积。

由于以上的这些操作都属于同一个RUN命令，因此这最终会产生一个相对小的镜像层，尽管在命令最开始的时候，我们为了构建最终的产品，安装了将近212MB的依赖。如果这些操作分布在不同的层，清除操作实际上不会真正地在最终镜像上删除这些文件，相反，只是将这些文件隐藏了起来。

最后一条：

```bash
CMD ["curl"]
```

docker run image命令将会默认调用curl命令。当然这也能够替换为ENTRYPOINT，但是我并不介意CMD能够简单地通过docker run被重新赋值。

构建并且运行镜像

```bash
docker build -t yourname/curl .
```

一旦构建完镜像，运行镜像就显得非常直接了。让我们来检查看看一切是否按照nghttp2.org上描述的那样工作。-s表示启动安静模式，--http2表示使用HTTP2协议，-I能够返回请求头，以此验证我们使用了正确的协议。

```
docker run curl:latest curl -s --http2 -I https://nghttp2.org
```

k8s运行

```
kubectl run curl -it --rm --image=curl:latest --image-pull-policy=IfNotPresent -- curl -s --http2 -I https://nghttp2.org
```
