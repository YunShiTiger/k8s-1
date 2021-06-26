## 项目说明：
### [etcd 部署](https://github.com/etcd-io/etcd )

可以单节点多节点都可以http 或者https 都行

```bash
mkdir -p /apps/{coredns/{conf,bin},etcd/{bin,data}}
```

#### etcd下载

```bash
wget https://github.com/etcd-io/etcd/releases/download/v3.4.7/etcd-v3.4.7-linux-amd64.tar.gz
tar xf etcd-v3.4.7-linux-amd64.tar.gz
mv etcd-v3.4.7-linux-amd64/etcd /apps/etcd/bin
mv etcd-v3.4.7-linux-amd64/etcdctl /usr/local/bin
```

#### coredns systemctl

```bash
cat << 'EOF' >/usr/lib/systemd/system/etcd.service 
[Unit]
Description=Etcd Server
After=neCNork.target
After=network-online.target
Wants=network-online.target
[Service]
Type=notify
ExecStart=/apps/etcd/bin/etcd \
--data-dir=/apps/etcd/data \
--logger=zap \
--enable-v2=true \
--name=etcd \
--listen-client-urls=http://192.168.31.20:2379,http://127.0.0.1:2379 \
--advertise-client-urls=http://192.168.31.20:2379 \
--max-request-bytes=33554432 \
--quota-backend-bytes=6442450944 \
--heartbeat-interval=250 \
--election-timeout=2000
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
```

#### 启动etcd

```bash
systemctl enable etcd
systemctl start etcd
```

#### 测试写入与读取

写入数据

```bash
etcdctl put /name/1 test
```

读取数据

```bash
etcdctl get  /name/1
```

### coredns 部署

上述配置文件表达的是：DNS server负责根域 . 的解析，其中插件是chaos且没有参数。

```bash
wget https://github.com/coredns/coredns/releases/download/v1.8.4/coredns_1.8.4_linux_amd64.tgz
tar zxf coredns_1.8.4_linux_amd64.tgz -C /apps/coredns/bin/
```

增加运行账户

```bash
useradd coredns -s /sbin/nologin
```

### Corefile 有两种方案
#### 方案1:
```bash
.:53 {
    errors
    log
    health {
        lameduck 5s
    }
    ready
   # 说明 etcd 后面给本地需要解析的域名 
   etcd xxx.com dddd.cn xxx.net {
      fallthrough
      path /coredns
      endpoint http://192.168.31.20:2379 #http://192.168.2.89:2379
      Etls /apps/coredns/ssl/etcd.pem /apps/coredns/ssl/etcd-key.pem /apps/coredns/ssl/ca.pem
   }
    prometheus :9153
    forward . 223.5.5.5:53 114.114.114.114:53 1.2.4.8:53 119.29.29.29:53
    cache 30
    reload 6s
    loadbalance
}
#指定域名使用dns 服务解析 例如解析K8S 集群域名 
  cluster.local {
  forward . 172.100.0.10:53
  }
```
#### 方案2: 
```bash
# 添加本地解析域名
xxxx.net {
    etcd {
        path /coredns
        endpoint http://192.168.31.20:2379 #https://192.168.2.89:2379
        #tls /apps/coredns/ssl/etcd.pem /apps/coredns/ssl/etcd-key.pem /apps/coredns/ssl/ca.pem
        fallthrough
    }
    cache
    loadbalance
}
# 添加本地解析域名
ddddd.com {
    etcd {
        path /coredns
        endpoint http://192.168.31.20:2379
        #tls /apps/coredns/ssl/etcd.pem /apps/coredns/ssl/etcd-key.pem /apps/coredns/ssl/ca.pem
        fallthrough
    }
    cache
   loadbalance
}
# 添加本地解析域名
yyyy.cn {
    etcd {
        path /coredns
        endpoint http://192.168.31.20:2379
        #tls /apps/coredns/ssl/etcd.pem /apps/coredns/ssl/etcd-key.pem /apps/coredns/ssl/ca.pem
        fallthrough
    }
    cache
    loadbalance
}

#指定域名使用dns 服务解析 例如解析K8S 集群域名 
cluster.local {
forward . 172.100.0.10:53
}

# 解析外部域名
. {
    prometheus :9153
    forward .  223.5.5.5:53 114.114.114.114:53 1.2.4.8:53 119.29.29.29:53
    loadbalance
    log
    cache 30
    reload 6s
}
```
#### 不支持外部cname 解析 只支持本地cname 解析 配置方案 这样无法接入外部cdn

```yaml
.:53 {
    errors
    health {
        lameduck 5s
    }
    ready
    etcd {
         path /coredns
         endpoint http://192.168.31.20:2379
         #tls /opt/k8s/cfssl/pki/etcd/etcd.pem /opt/k8s/cfssl/pki/etcd/etcd-key.pem /opt/k8s/cfssl/pki/etcd/ca.pem
         fallthrough
   }
    prometheus :9153
    forward . 223.5.5.5:53 114.114.114.114:53 1.2.4.8:53 119.29.29.29:53
    cache 30
    reload 6s
    loadbalance      
}
  cluster.local {
  forward . 172.100.0.10:53
  } 
```
配置

```bash
cat << EOF >/apps/coredns/conf/Corefile
.:53 {
  hosts {
    # 自定义hosts解析
    # 如果有大量自定义域名解析那么建议用file插件使用 符合RFC 1035规范的DNS解析配置文件
    192.168.31.150 sms.service
    192.168.31.2 search.service
    ttl 60 # ttl
    reload 1m # 重载hosts配置
    fallthrough  # 继续执行
  }
   etcd {   # 配置启用etcd插件,后面可以指定域名,例如 etcd test.com {
        stubzones # 启用存根区域功能。 stubzone仅在位于指定的第一个区域下方的etcd树中完成
        path /coredns # etcd里面的路径 默认为/skydns，以后所有的dns记录就是存储在该存根路径底下
        endpoint http://192.168.31.20:2379 # etcd访问地址，多个空格分开
        
        # upstream设置要使用的上游解析程序解决指向外部域名的在etcd（认为CNAME）中找到的外部域名。
        upstream 223.5.5.5:53 114.114.114.114:53 1.2.4.8:53 119.29.29.29:53 
        
        fallthrough # 如果区域匹配但不能生成记录，则将请求传递给下一个插件
        # tls CERT KEY CACERT # 可选参数，etcd认证证书设置
    }
   etcd xxx.com dddd.cn xxx.net {
      fallthrough
      path /coredns
      endpoint http://192.168.31.20:2379
      #tls /apps/coredns/ssl/etcd.pem /apps/coredns/ssl/etcd-key.pem /apps/coredns/ssl/ca.pem
   }
  # 最后所有的都转发到系统配置的上游dns服务器去解析
  forward . 223.5.5.5:53 114.114.114.114:53 1.2.4.8:53 119.29.29.29:53
  cache 120 # 缓存时间ttl
  reload 6s # 自动加载配置文件的间隔时间
  log # 输出日志
  errors # 输出错误
}
    wzxmt.com:53 {              #外部dns
    errors
    cache 30
    forward . 10.0.0.20
    }
EOF
```

#### 授权

```bash
chown -R coredns. /apps/coredns 
```

#### coredns systemctl

```bash
cat << EOF >/usr/lib/systemd/system/coredns.service
[Unit]
Description=CoreDNS DNS server
Documentation=https://coredns.io
After=network.target

[Service]
PermissionsStartOnly=true
LimitNOFILE=1048576
LimitNPROC=512
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
User=coredns
WorkingDirectory=~
ExecStart=/apps/coredns/bin/coredns -conf=/apps/coredns/conf/Corefile
ExecReload=/bin/kill -SIGUSR1 $MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
```

#### 启动服务

```bash
systemctl enable coredns
systemctl start coredns
```

### 测试添加相应记录

#### A记录

```
etcdctl put /coredns/com/leffss/www '{"host":"1.1.1.1","ttl":10}'
```

- etcd的目录结构和域名是相反的，即上面表示域名：[www.leffss.com](http://www.leffss.com/)
- ttl值设置60s后，coredns每60s才会到etcd读取这个域名的记录一次

查询结果：

```
[root@dns conf]# dig @localhost +short www.leffss.com      
1.1.1.1
```

如果想添加多条记录，让coredns轮询，方法如下：

```
etcdctl put /coredns/com/leffss/www/x1 '{"host":"1.1.1.2","ttl":10}'
etcdctl put /coredns/com/leffss/www/x2 '{"host":"1.1.1.3","ttl":10}'
```

- x1和x2可以自定义，比如a、b、c等
- 设置多个AAAA、CNAME等方法类似
- 添加/coredns/com/leffss/www/x1、x2后，请求www.leffss.com就不会再读取/coredns/com/leffss/www，可以使用etcdctl del /coredns/com/leffss/www删除值

查询结果：

```
[root@dns conf]# dig @localhost +short www.leffss.com      
1.1.1.2
1.1.1.3
```

**注意：**如果想让取消设置的轮询值，需要删除/coredns/com/leffss/www/x1与/coredns/com/leffss/www/x2

#### AAAA记录

```
etcdctl put /coredns/com/leffss/www '{"host":"1002::4:2","ttl":10}'
```

查询结果：

```
[root@dns conf]# dig -t AAAA @localhost +short www.leffss.com    
1002::4:2
```

#### CNAME记录

```
etcdctl put /coredns/com/leffss01/www '{"host":"www.baidu.com","ttl":10}'
```

查询结果：

```
[root@dns conf]# dig -t CNAME @localhost +short www.leffss01.com 
www.baidu.com.
```

- 这里cname设置成外部百度域名，按理说coredns应该也把这个cname记录继续解析成www.baidu.cm的IP地址，但是经过测试发现请求www.leffss.com只能解析到CNAME：[www.baidu.com](http://www.baidu.com/)，无法继续解析，原因未知，以后研究

#### SRV记录

```
etcdctl put /coredns/com/leffss/www '{"host":"www.baidu.com","port":80,"ttl":10}'
```

- SRV记录和CNAME记录类似，只是多了port，它们的添加方法其实可以通用

查询结果：

```
[root@dns conf]# dig -t SRV @localhost +short www.leffss.com 
10 50 0 x1.www.leffss.com.
10 50 0 x2.www.leffss.com.
```

#### TXT记录

```
etcdctl put /coredns/com/leffss/www '{"text":"This is text!","ttl":10}'  
```

查询结果：

```
[root@dns conf]# dig -t TXT @localhost +short www.leffss.com
"This is text!"
```



