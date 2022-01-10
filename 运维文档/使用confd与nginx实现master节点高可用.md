## 下载confd

```bash
mkdir -p confd && cd  confd
wget https://github.com/kelseyhightower/confd/releases/download/v0.16.0/confd-0.16.0-linux-amd64
mv confd-0.16.0-linux-amd64  confd
chmod +x confd
```

## 生成confd 配置

```bash
mkdir -p conf.d templates
```

生成confd 配置文件

```bash
cat << EOF >conf.d/nginx.toml
[template]
src = "nginx.tmpl"
dest = "/etc/nginx/conf/nginx.conf"
keys = [
    "CP_HOSTS",
]
EOF
```

 生成模版文件

```nginx
cat << 'EOF' >templates/nginx.tmpl
user nginx;
error_log stderr notice;
{{ $servers := split (getenv "CPU_NUM") "," }}{{range $servers}}
worker_processes {{.}};
{{end}}
master_process on;
worker_priority 1;
worker_shutdown_timeout 10s;
worker_rlimit_nofile 4096;
events {
  multi_accept on;
  use epoll;
  worker_connections 65535;
}

stream {
        upstream kube_apiserver {
          hash  consistent;
          {{ $servers := split (getenv "CP_HOSTS") "," }}{{range $servers}}
          server {{.}}:{{ getenv "TARGET_PORT"}} weight=6 max_fails=5 fail_timeout=10s;
          {{end}}
        }

        server {
          {{ $servers := split (getenv "HOST_PORT") "," }}{{range $servers}}
            listen        {{.}};
            listen        [::]:{{.}};
            {{end}}
            proxy_socket_keepalive on;
            proxy_buffer_size 512k;
            proxy_pass    kube_apiserver;
            proxy_timeout 5m;
            proxy_connect_timeout 5s;
      }
}
EOF
```

生成启动文件

```bash
cat << EOF >nginx-proxy
#!/bin/sh
confd -onetime -backend env
mkdir -p /etc/nginx/cache && cd /etc/nginx/cache
mkdir -p client_temp proxy_temp fastcgi_temp uwsgi_temp scgi_temp
chown -R nginx:nginx /etc/nginx
nginx -g 'daemon off;'
EOF
chmod +x nginx-proxy
```

## dockerfile

```bash
cat << 'EOF' >Dockerfile
# 基础镜像
FROM alpine:3.3
# 设置环境变量
ENV NGINX_VERSION 1.20.0
# 工作目录
WORKDIR /tmp
# 编译安装NGINX
RUN NGINX_CONFIG="\
      --prefix=/etc/nginx \
      --sbin-path=/usr/sbin/nginx \
      --conf-path=/etc/nginx/conf/nginx.conf \
      --error-log-path=/etc/nginx/logs/error.log \
      --http-log-path=/etc/nginx/logs/access.log \
      --pid-path=/etc/nginx/run/nginx.pid \
      --lock-path=/etc/nginx/run/nginx.lock \
      --http-client-body-temp-path=/etc/nginx/cache/client_temp \
      --http-proxy-temp-path=/etc/nginx/cache/proxy_temp \
      --http-fastcgi-temp-path=/etc/nginx/cache/fastcgi_temp \
      --http-uwsgi-temp-path=/etc/nginx/cache/uwsgi_temp \
      --http-scgi-temp-path=/etc/nginx/cache/scgi_temp \
      --user=nginx \
      --group=nginx \
      --with-pcre \
      --with-pcre-jit \
      --with-http_ssl_module \
      --with-http_v2_module \
      --with-http_realip_module \
      --with-http_stub_status_module \
      --with-http_gzip_static_module \
      --with-stream \
      --with-stream_realip_module \
      --with-stream_ssl_module \
      --with-stream_ssl_preread_module \
      " \
        && sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
        && apk update && apk upgrade \
        && addgroup -S nginx \
        && adduser -D -S -s /sbin/nologin -G nginx nginx \
        && apk add --no-cache --virtual .build-deps \
        build-base \
        curl \
        linux-headers \
        openssl-dev \
        pcre-dev \
        zlib-dev \
        openssl \
        pcre \
        zlib \
        && curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz \
        && tar -xzf nginx-$NGINX_VERSION.tar.gz \
        && cd  nginx-$NGINX_VERSION \
        && ./configure $NGINX_CONFIG \
        && make \
        && make install
# 构建confd nginx 镜像
FROM alpine:3.3
#COPY 编译结果  
COPY --from=0  /usr/sbin/nginx /usr/sbin/nginx
COPY --from=0  /etc/nginx  /etc/nginx  
ADD confd  /usr/sbin/confd
ADD conf.d /etc/confd/conf.d 
ADD templates /etc/confd/templates
ADD nginx-proxy /usr/bin/nginx-proxy
# 安装基础
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
   && apk update && apk upgrade \
   && apk add -U --no-cache  \ 
   curl \
   pcre \
   ca-certificates \
   tzdata \
   && addgroup -S nginx \
   && adduser -D -S -s /sbin/nologin -G nginx nginx \
   && rm -rf /var/cache/apk/* \
   && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
   && apk del tzdata
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/nginx-proxy"]
EOF
```

## 构建镜像

```bash
docker build -t nginx-proxy:v1.20.0 .
```

## 测试生成的镜像

单个IP

```bash
docker run --name=ha-test -d --network=host -e "CP_HOSTS=10.0.0.80" -e "CPU_NUM=1" -e "HOST_PORT=8443" -e "TARGET_PORT=6443" nginx-proxy:v1.20.0 CP_HOSTS=10.0.0.80
```

多ip

```bash
docker run --name=ha-tests -d --network=host -e "CP_HOSTS=10.0.0.80,10.0.0.90" -e "CPU_NUM=1" -e "HOST_PORT=8443" -e "TARGET_PORT=6443" nginx-proxy:v1.20.0 CP_HOSTS=10.0.0.80,10.0.0.90
```

测试

```bash
[root@k8s confd]# docker exec -ti ha-test curl -k https://127.0.0.1:8443
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {
    
  },
  "status": "Failure",
  "message": "Unauthorized",
  "reason": "Unauthorized",
  "code": 401
}
```

代理正常有数据返回

## k8s 使用 nginx-proxy

使用静态pod

```yaml
cat << EOF >${K8S_DIR}/manifests/kube-apiserver-ha-proxy.yaml 
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-apiserver-ha-proxy
    tier: control-plane  
  name: kube-apiserver-ha-proxy
  namespace: kube-system
spec:
  containers:
  - args:
    - "CP_HOSTS=${MASTER_CLUSTER_IP}"
    image: nginx-proxy:v1.20.0
    imagePullPolicy: IfNotPresent
    name: kube-apiserver-ha-proxy
    env:
    - name: CPU_NUM
      value: "1"
    - name: TARGET_PORT
      value: "6443"
    - name: HOST_PORT
      value: "8443"
    - name: CP_HOSTS
      value: "${MASTER_CLUSTER_IP}"
  hostNetwork: true
  priorityClassName: system-cluster-critical
EOF
```

docker运行

```bash
docker run --name=ha-tests -d --network=host -e "CP_HOSTS=10.0.0.80,10.0.0.90" -e "CPU_NUM=1" -e "HOST_PORT=8443" -e "TARGET_PORT=6443" nginx-proxy:v1.20.0 CP_HOSTS=10.0.0.80,10.0.0.90
```

