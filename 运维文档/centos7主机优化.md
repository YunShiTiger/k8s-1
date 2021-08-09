#### 修改源

```bash
mv /etc/yum.repos.d/CentOS-Base.repo{,.bak} && mv /etc/yum.repos.d/epel.repo{,.bak}
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
curl -o /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
```

#### 安装软件

```bash
yum -y install vim wget bash-completion lrzsz nc tree htop iftop net-tools screen lsof tcpdump sysstat dos2unix telnet git
```

#### 关闭邮件服务

```bash
systemctl stop postfix.service
systemctl disable postfix.service
```

#### 关闭防火墙

```bash
systemctl stop firewalld.service
systemctl disable firewalld.service
```

#### 调整系统时区

```bash
# 设置系统时区为中国/上海
timedatectl set-timezone Asia/Shanghai
# 将当前的 UTC 时间写入硬件时钟timedatectl set-local-rtc 0
# 重启依赖于系统时间的服务systemctl restart rsyslog
systemctl restart crond
#同步时间
systemd-analyze time
```

#### 开机自启优化

```bash
systemctl list-unit-files|egrep "^ab|^aud|^kdump|vm|^md|^mic|^post|lvm" \
|awk '{print $1}'|sed -r 's#(.*)#systemctl disable &#g'|bash
```

#### 关闭selinux

```bash
setenforce 0
sed -i "s/^SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config 
```

#### ssh的优化

```bash
vim /etc/ssh/sshd_config
#修改
GSSAPIAuthentication yes改成no  #启用时登陆的时候客户端需要对服务器端的IP地址进行反解析
#添加
UseDNS no #不使用dns解析
```

#### 关闭网卡图形化设置模式

```bash
systemctl stop NetworkManager.service 
systemctl disable NetworkManager.service
```

#### 加大描述符

```bash
cat << 'EOF' >>/etc/security/limits.conf
*       soft    nofile  655350
*       hard    nofile  655350
*       soft    nproc   655350
*       hard    nproc   655350
*       soft    core    unlimited
*       hard    core    unlimited
EOF
```

#### 内核优化

```bash
cat<< 'EOF' >>/etc/sysctl.d/99-sysctl.conf
#CTCDN系统优化参数
#关闭ipv6节省系统资源
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
#决定检查过期多久邻居条目
net.ipv4.neigh.default.gc_stale_time=120
#使用arp_announce / arp_ignore解决ARP映射问题
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.all.arp_announce=2
net.ipv4.conf.lo.arp_announce=2
# 避免放大攻击
net.ipv4.icmp_echo_ignore_broadcasts = 1
# 开启恶意icmp错误消息保护
net.ipv4.icmp_ignore_bogus_error_responses = 1
#关闭路由转发
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
#开启反向路径过滤
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
#处理无源路由的包
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
#关闭sysrq功能
kernel.sysrq = 0
#core文件名中添加pid作为扩展名
kernel.core_uses_pid = 1
# 开启SYN洪水攻击保护
net.ipv4.tcp_syncookies = 1
#修改消息队列长度
kernel.msgmnb = 65536
kernel.msgmax = 65536
#设置最大内存共享段大小bytes
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
#timewait的数量，默认180000
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 16384 4194304
net.core.wmem_default = 8388608
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
#每个网络接口接收数据包的速率比内核处理这些包的速率快时，允许送到队列的数据包的最大数目
net.core.netdev_max_backlog = 262144
#限制仅仅是为了防止简单的DoS 攻击
net.ipv4.tcp_max_orphans = 3276800
#未收到客户端确认信息的连接请求的最大值
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_timestamps = 0
#内核放弃建立连接之前发送SYNACK 包的数量
net.ipv4.tcp_synack_retries = 1
#内核放弃建立连接之前发送SYN 包的数量
net.ipv4.tcp_syn_retries = 1
#启用timewait 快速回收
net.ipv4.tcp_tw_recycle = 1
#开启重用。允许将TIME-WAIT sockets 重新用于新的TCP 连接
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_mem = 94500000 915000000 927000000
net.ipv4.tcp_fin_timeout = 1
#当keepalive 起用的时候，TCP 发送keepalive 消息的频度。缺省是2 小时
net.ipv4.tcp_keepalive_time = 1800
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
#允许系统打开的端口范围
net.ipv4.ip_local_port_range = 1024 65000
#修改防火墙表大小，默认65536
net.netfilter.nf_conntrack_max=655350
net.netfilter.nf_conntrack_tcp_timeout_established=1200
# 确保无人能修改路由表
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
EOF
```

#### histroy增加时间撮

```bash
export HISTTIMEFORMAT='%F %T  '
```

永久

```bash
cat << 'EOF' >>~/.bashrc
export HISTTIMEFORMAT='%F %T  '
EOF
source ~/.bashrc
```
