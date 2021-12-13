# [etcd 部署](https://github.com/etcd-io/etcd )

可以单节点多节点都可以http 或者https 都行

```bash
mkdir -p /apps/{coredns/{conf,bin},etcd/{bin,data,ssl}}
```

添加普通用户

```bash
useradd coredns -s /sbin/nologin
```

## etcd下载

```bash
wget https://github.com/etcd-io/etcd/releases/download/v3.5.0/etcd-v3.5.0-linux-amd64.tar.gz
tar xf etcd-v3.5.0-linux-amd64.tar.gz
chown -R coredns. etcd-v3.5.0-linux-amd64
mv etcd-v3.5.0-linux-amd64/etcd /apps/etcd/bin
mv etcd-v3.5.0-linux-amd64/etcdctl /usr/local/bin
```

## etcd部署

#### cfssl下载

```
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -O /usr/local/bin/cfssl
wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -O /usr/local/bin/cfssljson
wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 -O /usr/local/bin/cfssl-certinfo
chmod +x /usr/local/bin/cfssl*
```

#### 生成证书

```bash
cd /apps/etcd/ssl
#ca
cat >ca-config.json << EOF
{"signing":{"default":{"expiry":"87600h"},"profiles":{"kubernetes":{"usages":["signing","key encipherment","server auth","client auth"],"expiry":"87600h"}}}}
EOF
cat > ca-csr.json << EOF 
{"CN": "kubernetes","key": {"algo": "rsa","size": 2048},"names":[{"C": "CN","ST": "BeiJing","L": "BeiJing","O": "kubernetes","OU": "k8s"}],"ca":{"expiry":"87600h"}}
EOF
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
#etcd
cat > etcd-csr.json <<EOF 
{"CN":"etcd","key":{"algo":"rsa","size":2048},"names":[{"C":"CN","ST":"BeiJing","L":"BeiJing","O":"kubernetes","OU":"etcd"}]}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -hostname=127.0.0.1,10.0.0.31,10.0.0.32,10.0.0.33 -profile=kubernetes etcd-csr.json|cfssljson -bare etcd
```

删除证书请求

```bash
rm -f *.json *csr*
```

证书详细信息

```bash
cfssl-certinfo -cert etcd.pem
```

#### systemctl管理etcd

环境变量

```bash
cat << EOF >>/root/.bash_profile

ENDPOINTS="https://10.0.0.31:2379,https://10.0.0.32:2379,https://10.0.0.33:2379"
ETCD_ENDPOINTS="etcd-m1=https://10.0.0.31:2380,etcd-m2=https://10.0.0.32:2380,etcd-m3=https://10.0.0.33:2380"
ETCD_SSL=/apps/etcd/ssl
ETCD_DIR=/apps/etcd
ETCD_DATA_DIR=/apps/etcd/data
EOF
source ~/.bash_profile
```

生成配置

```bash
cat << EOF >/usr/lib/systemd/system/etcd.service
[Unit]
Description=Etcd Server
After=neCNork.target
After=network-online.target
Wants=network-online.target
[Service]
Type=notify
User=coredns
ExecStart=${ETCD_DIR}/bin/etcd \\
  --auto-compaction-mode=periodic \\
  --auto-compaction-retention=1 \\
  --data-dir=${ETCD_DATA_DIR} \\
  --enable-v2=true \\
  --logger=zap \\
  --name=etcd-$(hostname) \\
  --peer-client-cert-auth \\
  --advertise-client-urls=https://$(hostname -I|awk '{print $1}'):2379 \\
  --initial-advertise-peer-urls=https://$(hostname -I|awk '{print $1}'):2380 \\
  --listen-client-urls=https://$(hostname -I|awk '{print $1}'):2379 \\
  --listen-peer-urls=https://$(hostname -I|awk '{print $1}'):2380 \\
  --initial-cluster=${ETCD_ENDPOINTS} \\
  --initial-cluster-state=new \\
  --initial-cluster-token=etcd-cluster \\
  --cert-file=${ETCD_SSL}/etcd.pem \\
  --peer-cert-file=${ETCD_SSL}/etcd.pem \\
  --key-file=${ETCD_SSL}/etcd-key.pem \\
  --trusted-ca-file=${ETCD_SSL}/ca.pem \\
  --peer-key-file=${ETCD_SSL}/etcd-key.pem \\
  --peer-trusted-ca-file=${ETCD_SSL}/ca.pem \\
  --quota-backend-bytes=17179869184 \\
  --max-request-bytes=33554432 \\
  --heartbeat-interval=6000 \\
  --election-timeout=30000 \\
  --snapshot-count=5000 
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
```

#### 启动etcd

```bash
systemctl enable --now etcd
```

检查etcd集群状态

```
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} endpoint health
```

#### 测试写入与读取

写入数据

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} put /name/1 test
```

读取数据

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} get  /name/1
```

# coredns 部署

上述配置文件表达的是：DNS server负责根域 . 的解析，其中插件是chaos且没有参数。

```bash
wget https://github.com/coredns/coredns/releases/download/v1.8.6/coredns_1.8.6_linux_amd64.tgz
tar zxf coredns_1.8.6_linux_amd64.tgz -C /apps/coredns/bin/
```

### Corefile 有两种方案
#### 方案1
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
      tls /apps/etcd/ssl/etcd.pem /apps/etcd/ssl/etcd-key.pem /apps/etcd/ssl/ca.pem
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
#### 方案2
```bash
# 添加本地解析域名
xxxx.net {
    etcd {
        path /coredns
        endpoint http://192.168.31.20:2379 #https://192.168.2.89:2379
        tls /apps/etcd/ssl/etcd.pem /apps/etcd/ssl/etcd-key.pem /apps/etcd/ssl/ca.pem
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
        tls /apps/etcd/ssl/etcd.pem /apps/etcd/ssl/etcd-key.pem /apps/etcd/ssl/ca.pem
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
        tls /apps/etcd/ssl/etcd.pem /apps/etcd/ssl/etcd-key.pem /apps/etcd/ssl/ca.pem
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
         tls /apps/etcd/ssl/etcd.pem /apps/etcd/ssl/etcd-key.pem /apps/etcd/ssl/ca.pem
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
    10.0.0.150 sms.service
    ttl 60 # ttl
    reload 1m # 重载hosts配置
    fallthrough  # 继续执行
  }
   etcd {   # 配置启用etcd插件,后面可以指定域名,例如 etcd test.com {
        stubzones # 启用存根区域功能。 stubzone仅在位于指定的第一个区域下方的etcd树中完成
        path /coredns # etcd里面的路径 默认为/skydns，以后所有的dns记录就是存储在该存根路径底下
        endpoint ${ENDPOINTS} # etcd访问地址，多个空格分开
        
        # upstream设置要使用的上游解析程序解决指向外部域名的在etcd（认为CNAME）中找到的外部域名。
        upstream 223.5.5.5:53 114.114.114.114:53 1.2.4.8:53 119.29.29.29:53 
        
        fallthrough # 如果区域匹配但不能生成记录，则将请求传递给下一个插件
        # tls CERT KEY CACERT # 可选参数，etcd认证证书设置
        tls ${ETCD_SSL}/etcd.pem ${ETCD_SSL}/etcd-key.pem ${ETCD_SSL}/ca.pem
    }
   etcd wzxmt.com dddd.cn xxx.net {
      fallthrough
      path /coredns
      endpoint ${ENDPOINTS}
      tls ${ETCD_SSL}/etcd.pem ${ETCD_SSL}/etcd-key.pem ${ETCD_SSL}/ca.pem
   }
  # 最后所有的都转发到系统配置的上游dns服务器去解析
  prometheus $(hostname -I|awk '{print $1}'):9153
  forward . 223.5.5.5:53 114.114.114.114:53 1.2.4.8:53 119.29.29.29:53
  cache 120 # 缓存时间ttl
  reload 6s # 自动加载配置文件的间隔时间
  log # 输出日志
  errors # 输出错误
  #health #查看健康状况 8080
}
    test.com:53 {              #外部dns
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
WorkingDirectory=/apps/coredns
ExecStart=/apps/coredns/bin/coredns -conf=/apps/coredns/conf/Corefile
ExecReload=/bin/kill -SIGUSR1 $MAINPID
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
```

#### 启动服务

```bash
systemctl enable coredns --now
```

### 测试添加相应记录

dns接入

```bash
#vim /etc/sysconfig/network-scripts/ifcfg-eth0
...
DNS1="10.0.0.100"
...
```

安装dig

```bash
yum install bind-utils
```

#### A记录

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} put /coredns/com/wzxmt/www '{"host":"10.0.0.80","ttl":10}'
```

- etcd的目录结构和域名是相反的，即上面表示域名：[www.wzxmt.com](http://www.wzxmt.com/)
- ttl值设置60s后，coredns每60s才会到etcd读取这个域名的记录一次

查询结果：

```bash
[root@dns ~]# dig @localhost +short www.wzxmt.com
10.0.0.80
```

如果想添加多条记录，让coredns轮询，方法如下：

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} put /coredns/com/wzxmt/www/x1 '{"host":"10.0.0.90","ttl":10}'

etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} put /coredns/com/wzxmt/www/x2 '{"host":"10.0.0.100","ttl":10}'
```

- x1和x2可以自定义，比如a、b、c等
- 设置多个AAAA、CNAME等方法类似
- 添加/coredns/com/wzxmt/www/x1、x2后，请求www.wzxmt.com就不会再读取/coredns/com/wzxmt/www，可以使用etcdctl del /coredns/com/wzxmt/www删除值

查询结果：

```bash
[root@dns ~]# dig @localhost +short www.wzxmt.com      
10.0.0.90
10.0.0.100
```

**注意：**如果想让取消设置的轮询值，需要删除/coredns/com/wzxmt/www/x1与/coredns/com/wzxmt/www/x2

#### AAAA记录

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} put /coredns/com/wzxmt/test '{"host":"1002::4:2","ttl":10}'
```

查询结果：

```bash
[root@dns ~]# dig -t AAAA @localhost +short test.wzxmt.com
1002::4:2
```

#### CNAME记录

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} put /coredns/com/wzxmt01/www '{"host":"www.baidu.com","ttl":10}'
```

查询结果：

```bash
[root@dns ~]# dig -t CNAME @localhost +short www.wzxmt01.com 
www.baidu.com.
```

- 这里cname设置成外部百度域名，按理说coredns应该也把这个cname记录继续解析成www.baidu.cm的IP地址，但是经过测试发现请求www.wzxmt.com只能解析到CNAME：[www.baidu.com](http://www.baidu.com/)，无法继续解析，原因未知，以后研究

#### SRV记录

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} put /coredns/com/wzxmt/www '{"host":"www.baidu.com","port":80,"ttl":10}'
```

- SRV记录和CNAME记录类似，只是多了port，它们的添加方法其实可以通用

查询结果：

```bash
[root@dns ~]# dig -t SRV @localhost +short www.wzxmt.com 
10 50 0 x1.www.wzxmt.com.
10 50 0 x2.www.wzxmt.com.
```

#### TXT记录

```bash
etcdctl --cacert=${ETCD_SSL}/ca.pem \
--cert=${ETCD_SSL}/etcd.pem \
--key=${ETCD_SSL}/etcd-key.pem \
--endpoints=${ENDPOINTS} put /coredns/com/wzxmt/www '{"text":"This is text!","ttl":10}'  
```

查询结果：

```bash
[root@dns ~]# dig -t TXT @localhost +short www.wzxmt.com
"This is text!"
```

## coredns 高可用

按照前面的部署方式部署3个coredns服务

通过nginx转发实现高可用

```nginx
stream {
    upstream dns_upstreams {
        server 10.0.0.31:53; 
        server 10.0.0.32:53;
        server 10.0.0.33:53; 
    }
    server {
        listen 53 udp;
        proxy_pass dns_upstreams;
        proxy_timeout 1s;
        proxy_responses 1;
        error_log logs/dns.log;
    }
}
```

