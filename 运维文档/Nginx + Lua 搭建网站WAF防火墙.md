## 一、nginx软waf应用防火墙

### 简介

WAF（Web Application Firewall），中文名叫做“Web应用防火墙”；WAF的定义是这样的：Web应用防火墙是通过执行一系列针对HTTP/HTTPS的安全策略来专门为Web应用提供保护的一款产品,通过从上面对WAF的定义中，我们可以很清晰地了解到：WAF是一种工作在应用层的、通过特定的安全策略来专门为Web应用提供安全防护的产品。

### waf防护顺序

先检查白名单，通过即不检测；再检查黑名单，不通过即拒绝，检查UA，UA不通过即拒绝；检查cookie；URL检查;URL参数检查，post检查。

### WAF用途

- 支持IP白名单和黑名单功能，直接将黑名单的IP访问拒绝（新增cdip功能支持ip段）
- 支持URL白名单，将不需要过滤的URL进行定义
- 支持User-Agent的过滤，匹配自定义规则中的条目，然后进行处理
- 支持CC攻击防护，单个URL指定时间的访问次数，超过设定值（新增针对不同域名）
- 支持Cookie过滤，匹配自定义规则中的条目，然后进行处理
- 支持URL过滤，匹配自定义规则中的条目，如果用户请求的URL包含这些
- 支持URL参数过滤，原理同上
- 支持日志记录，将所有拒绝的操作，记录到日志中去
- 新增支持拉黑缓存（默认600秒）

## 二、 安装

### 1、部署环境说明：　　

```
CentOS Linux release 7.5. (Core)
```

### 2、安装依赖包：

```
yum -y install gcc gcc-c++ zlib zlib-devel openssl openssl-devel pcre pcre-devel
```

### 3、安装LuaJIT2.0

LuaJIT是采用C语言写的Lua代码的解释器

```bash
cd /usr/local/src/
wget http://luajit.org/download/LuaJIT-2.0.5.tar.gz
tar xf LuaJIT-2.0.5.tar.gz
cd LuaJIT-2.0.5
make install PREFIX=/usr/local/LuaJIT
```

### 4、安装ngx_devel_kit模块

NDK（nginx development kit）模块是一个拓展nginx服务器核心功能的模块，第三方模块开发可以基于它来快速实现。

```bash
wget https://github.com/vision5/ngx_devel_kit/archive/refs/tags/v0.3.1.tar.gz
tar xf v0.3.1.tar.gz
```

### 5、安装nginx_lua_module模块

```bash
wget https://github.com/openresty/lua-nginx-module/archive/v0.10.15.tar.gz
tar xf v0.10.15.tar.gz
```

### 6、导入环境变量：

```bash
echo "export LUAJIT_LIB=/usr/local/LuaJIT/lib" >> /etc/profile
echo "export LUAJIT_INC=/usr/local/LuaJIT/include/luajit-2.0" >> /etc/profile
source /etc/profile
```

### 7、共享lua动态库

加载lua库到ld.so.conf文件

```
echo "/usr/local/LuaJIT/lib" >> /etc/ld.so.conf
```

执行`ldconfig`让动态函式库加载到缓存中

```
ldconfig
```

### 8、编译安装Nginx

下载并解压

```bash
cd /usr/local/src
wget http://nginx.org/download/nginx-1.16.0.tar.gz
tar -zxvf nginx-1.16.0.tar.gz
cd nginx-1.16.0
```

添加用户与用户组

```bash
groupadd  nginx
useradd  -M  -s /sbin/nologin  -g  nginx  nginx
```

编译配置过程

```bash
./configure \
--user=nginx --group=nginx \
--prefix=/usr/local/nginx \
--with-http_stub_status_module \
--with-http_gzip_static_module \
--with-http_realip_module \
--with-http_sub_module \
--with-http_ssl_module \
--with-stream \
--add-module=/usr/local/src/ngx_devel_kit-0.3.0 \
--add-module=/usr/local/src/lua-nginx-module-0.10.13 \
--with-ld-opt="-Wl,-rpath,$LUAJIT_LIB"
```

编译安装

```bash
make -j2 && make install
```

添加环境变量

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

配置分离

```bash
mkdir -p /usr/local/nginx/conf/vhost
```

修改nginx.conf配置文件http模块下增加一行

```bash
include /usr/local/nginx/conf/vhost/*.conf;
```

### 9、授权目录

```bash
mkdir -p /usr/local/nginx/logs/hack
chown -R nginx /usr/local/nginx
chmod -R 755 /usr/local/nginx/logs/hack
```

### 10、测试

```bash
cat << 'EOF' >/usr/local/nginx/conf/vhost/test.conf
server {
    listen       80;
    server_name  test.wzxmt.com;
    charset utf-8; #默认编码为utf-8

    location / {
        root   html;
        index  index.html index.htm;
    }
    # 测试Nginx Lua
    location /hello {
        default_type 'text/plain';
        content_by_lua 'ngx.say("欢迎访问wzxmt~")';
    }
    # 测试获取客户端ip
    location /myip {
        default_type 'text/plain';
        content_by_lua '
        clientIP = ngx.req.get_headers()["x_forwarded_for"]
        ngx.say("IP:",clientIP)';  
    }
}
EOF
```

重启nginx

```
nginx -s reload
```

访问

http://test.wzxmt.com/hello

至此nginx支持WAF防护功能已经搭建完成！

## 三、使用说明

　　nginx配置文件路径为:/usr/local/nginx/conf/

　　把ngx_lua_waf下载到conf目录下,解压命名为waf

```
wget https://github.com/loveshell/ngx_lua_waf/archive/master.zip
unzip master.zip -d /usr/local/nginx/conf/
mv /usr/local/nginx/conf/ngx_lua_waf-master /usr/local/nginx/conf/waf
```

　　在nginx.conf的http段添加下面这段：

```
    lua_package_path "/usr/local/nginx/conf/waf/?.lua";
    lua_shared_dict limit 10m;
    init_by_lua_file  /usr/local/nginx/conf/waf/init.lua;
    access_by_lua_file /usr/local/nginx/conf/waf/waf.lua;
```

　　配置config.lua里的waf规则目录(一般在waf/conf/目录下)：

```
  RulePath = "/usr/local/nginx/conf/waf/wafconf/"   #绝对路径如有变动，需对应修改
```

　　然后重启nginx即可

　　**###配置文件详细说明：**

```json
RulePath = "/usr/local/nginx/conf/waf/wafconf/"
    --规则存放目录
    attacklog = "off"
    --是否开启攻击信息记录，需要配置logdir
    logdir = "/usr/local/nginx/logs/hack/"
    --log存储目录，该目录需要用户自己新建，切需要nginx用户的可写权限
    UrlDeny="on"
    --是否拦截url访问
    Redirect="on"
    --是否拦截后重定向
    CookieMatch = "on"
    --是否拦截cookie攻击
    postMatch = "on"
    --是否拦截post攻击
    whiteModule = "on"
    --是否开启URL白名单
    black_fileExt={"php","jsp"}
    --填写不允许上传文件后缀类型
    ipWhitelist={"127.0.0.1"}
    --ip白名单，多个ip用逗号分隔
    ipBlocklist={"1.0.0.1"}
    --ip黑名单，多个ip用逗号分隔
    CCDeny="on"
    --是否开启拦截cc攻击(需要nginx.conf的http段增加lua_shared_dict limit 10m;)
    CCrate = "100/60"
    --设置cc攻击频率，单位为秒.
    --默认1分钟同一个IP只能请求同一个地址100次
    html=[[Please go away~~]]
    --警告内容,可在中括号内自定义
    备注:不要乱动双引号，区分大小写
```

　　启动nginx：　

```
/usr/local/nginx/sbin/nginx
```

**###检查规则是否生效：**

　　部署完毕可以尝试如下命令：

```
curl http://your_ip/test.php?id=../etc/passwd
```

结果如下则说明规则生效（页面修改地址：/usr/local/nginx/conf/waf/config.lua）：

![img](https://bbsmax.ikafan.com/static/L3Byb3h5L2h0dHBzL2ltZzIwMTguY25ibG9ncy5jb20vYmxvZy8xNDA2MDU2LzIwMTgwOS8xNDA2MDU2LTIwMTgwOTE4MTI1MDIyMTUxLTE1Mzk4NTI5NDUucG5n.jpg)

　注意:默认，本机在白名单不过滤，可自行调整config.lua配置

```
###一些说明：
　　
过滤规则在wafconf下，可根据需求自行调整，每条规则需换行,或者用|分割     args里面的规则get参数进行过滤的
    url是只在get请求url过滤的规则
    post是只在post请求过滤的规则
    whitelist是白名单，里面的url匹配到不做过滤
    user-agent是对user-agent的过滤规则 默认开启了get和post过滤，需要开启cookie过滤的，编辑waf.lua取消部分--注释即可 日志文件名称格式如下:虚拟主机名_sec.log
```