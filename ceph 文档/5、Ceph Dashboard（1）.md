# Ceph Dashboard介绍
Ceph 的监控可视化界面方案很多----grafana、Kraken。但是从Luminous开始，Ceph 提供了原生的Dashboard功能，通过Dashboard可以获取Ceph集群的各种基本状态信息。
mimic版  (nautilus版)  dashboard 安装。如果是  (nautilus版) 需要安装 ceph-mgr-dashboard 

# 配置Ceph Dashboard
```
1、在每个mgr节点安装
# yum install ceph-mgr-dashboard -y 
2、开启mgr功能
ceph mgr module enable dashboard
3、生成并安装自签名的证书
ceph dashboard create-self-signed-cert  
4、创建一个dashboard登录用户名密码
ceph dashboard ac-user-create admin 123456 administrator 
5、查看服务访问方式
ceph mgr services
```
# 修改默认配置命令
```
指定集群dashboard的访问端口
ceph config set mgr mgr/dashboard/server_port 7000
指定集群 dashboard的访问IP
ceph config set mgr mgr/dashboard/server_addr 10.0.0.61
```
# 开启Object Gateway管理功能
```
1、创建rgw用户
radosgw-admin user create --uid=rgw --display-name=rgw --system
radosgw-admin user info --uid=rgw
2、提供Dashboard证书
ceph dashboard set-rgw-api-access-key $access_key
ceph dashboard set-rgw-api-secret-key $secret_key
3、刷新web页面
```

