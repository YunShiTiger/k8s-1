# nginx 1.16.0编译安装

#### 一、安装依赖

```
yum install gcc gcc-c++ pcre pcre-devel zlib zlib-devel openssl openssl-devel -y 
```

#### 二、下载[nginx](http://nginx.org/download/nginx-1.16.0.tar.gz)
可以到[nginx](http://nginx.org/)官网下载,或者通过以下链接下载

```
http://nginx.org/download/nginx-1.16.0.tar.gz
```
下载后通过tar -xvzf 进行解压，并进入到nginx目录下

```
tar xf nginx-1.16.0.tar.gz
cd nginx-1.16.0
```

#### 三、指定nginx编译参数
```
./configure --prefix=/usr/local/nginx --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_stub_status_module --with-http_gzip_static_module --with-pcre --with-stream --with-stream_ssl_module --with-stream_realip_module　　　　
```

　参数说明：
　　　　　　　　--prefix 用于指定nginx编译后的安装目录
　　　　　　　　--add-module 为添加的第三方模块
　　　　　　　　--with..._module 表示启用的nginx模块，如此处启用了好几个模块

#### 四、编译
　执行make 进行编译，如果编译成功的话会在第一步中objs中出现一个nginx的可执行文件

#### 五、安装
　执行make install 进行安装，安装后--prefix 中指定的安装目录下回出现如下目录结构　　　

```
conf
html
logs
sbin
```

#### 六、启动nginx
创建一个nginx软链接

```
ln -s /usr/local/nginx/sbin/nginx /usr/bin/nginx
```

查看配置文件是否正确：nginx -t 
启动：nginx
重启：nginx -s reload
停止：nginx -s stop或者是通过kill nginx进程号
查看版本及编译参数：nginx –V

#### 七、新增加模块
在已安装的nginx上进行添加模块

1）备份配置文件
2）执行nginx -V查看已编译参数，./configure + 已编译参数 + 添加新增模块；
3）make

编译完后，把objs中的nginx替换掉之前的nginx文件，然后重启nginx就行了；如果执行下一步的install，会导致之前安装的nginx被覆盖，比如之前配置好的nginx.conf文件
