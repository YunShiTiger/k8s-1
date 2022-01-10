#### 一、安装依赖

```bash
yum install gcc gcc-c++ pcre pcre-devel zlib zlib-devel openssl openssl-devel patch -y 
```

#### 二、下载[nginx](http://nginx.org/download/nginx-1.16.0.tar.gz)
```bash
cd /usr/local/src
git clone git://github.com/vozlt/nginx-module-sts.git 
git clone git://github.com/vozlt/nginx-module-stream-sts.git 
git clone git://github.com/vozlt/nginx-module-vts.git 
git clone https://github.com/yaoweibin/nginx_upstream_check_module.git
git clone https://gitee.com/mirrors/nginx_tcp_proxy_module.git
wget http://nginx.org/download/nginx-1.16.0.tar.gz
tar xf nginx-1.16.0.tar.gz
cd nginx-1.16.0
```
创建nginx用户组

 ```bash
groupadd nginx
useradd -M -s /sbin/nologin -g nginx nginx
 ```

#### 三、指定nginx编译参数

加载补丁

```
patch -p1 <../nginx_upstream_check_module/check_1.20.1+.patch
```

预编译

```bash
./configure \
--prefix=/usr/local/nginx \
--user=nginx \
--group=nginx \
--with-pcre \
--with-stream \
--with-pcre-jit \
--with-http_ssl_module \
--with-http_v2_module \
--with-http_realip_module \
--with-http_stub_status_module \
--with-http_gzip_static_module \
--with-stream_ssl_module \
--with-stream_realip_module \
--add-module=../nginx-module-sts \
--add-module=../nginx-module-stream-sts \
--add-module=../nginx-module-vts \
--add-module=../nginx_upstream_check_module
--add-module=../nginx_tcp_proxy_module
```

参数说明：
　　--prefix 用于指定nginx编译后的安装目录
　　--add-module 为添加的第三方模块
　　--with..._module 表示启用的nginx模块，如此处启用了好几个模块

#### 四、编译与安装
```bash
make && make install
```

#### 五、添加环境变量

 ```bash
echo 'export PATH=$PATH:/usr/local/nginx/sbin' >>/etc/profile
source /etc/profile
 ```

增加别名

```bash
cat << 'EOF' >>$HOME/.bashrc
alias ngc='cd /usr/local/nginx/conf'
alias ngl='cd /usr/local/nginx/logs'
EOF
source $HOME/.bashrc
```

#### 六、修改nginx配置

```nginx
cat << 'EOF' >/usr/local/nginx/conf/nginx.conf
user  nginx;
worker_processes  auto;
worker_rlimit_nofile 65535;
error_log  logs/error.log;
pid        logs/nginx.pid;
events {
    use epoll;
    worker_connections  65535;
}
include /usr/local/nginx/conf/stream/*.conf;
http {
    include       mime.types;
    default_type  application/octet-stream;
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
    access_log  logs/access.log  main;
    charset utf-8;
    server_names_hash_bucket_size 128;
    client_header_buffer_size 2k;
    large_client_header_buffers 4 4k;
    client_max_body_size 8m;
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 60;
    tcp_nodelay on;
    open_file_cache max=204800 inactive=20s;
    open_file_cache_min_uses 1;
    open_file_cache_valid 30s;
    gzip on;
    gzip_min_length 1k;
    gzip_buffers 4 16k;
    gzip_http_version 1.0;
    gzip_comp_level 2;
    gzip_types text/plain application/x-javascript text/css application/xml;
    gzip_vary on;
    include /usr/local/nginx/conf/vhost/*.conf;
}
EOF
```

创建目录

```bash
mkdir -p /usr/local/nginx/conf/{vhost,stream}
```

生成测试配置

http

```nginx
cat << 'EOF' >/usr/local/nginx/conf/vhost/test-http.conf
upstream cluster {
    # simple round-robin
    server 10.0.0.80:80;
    check interval=5000 rise=1 fall=3 timeout=4000;
    #check interval=3000 rise=2 fall=5 timeout=1000 type=ssl_hello;
    #check interval=3000 rise=2 fall=5 timeout=1000 type=http;
    #check_http_send "HEAD / HTTP/1.0\r\n\r\n";
    #check_http_expect_alive http_2xx http_3xx;
}
server {
    listen 80;
    location / {
      proxy_pass http://cluster;
    }
    location /status {
      check_status;
      access_log   off;
  }
}
EOF
```

tcp

```nginx
cat << 'EOF' >/usr/local/nginx/conf/vhost/test-http.conf
tcp {
  upstream server {
      server 10.100.138.15:8787;
      #check interval 健康检查时间间隔，单位为毫秒
      #rise 检查几次正常后，将server加入以负载列表中
      #fall 检查几次失败后，从负载队列移除server
      #timeout 检查超时时间，单位为毫秒
      check interval=3000 rise=2 fall=5 timeout=1000;
   }
   server {
      listen 8787;
      proxy_pass server;
      so_keepalive on; 
      tcp_nodelay on;  
  }
}
EOF
```

#### 七、授权并启动

```bash
chown -R nginx. /usr/local/nginx
nginx -t
nginx
```

#### 八、新增加模块

在已安装的nginx上进行添加模块

1、备份配置文件
2、执行nginx -V查看已编译参数，./configure + 已编译参数 + 添加新增模块；
3、make

编译完后，把objs中的nginx替换掉之前的nginx文件，然后重启nginx就行了；如果执行下一步的install，会导致之前安装的nginx被覆盖，比如之前配置好的nginx.conf文件
