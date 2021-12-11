## 快速部署jumpserver

## 1、概述

全球首款完全开源的堡垒机，使用GNU GPL v2.0开源协议，是符合 4A 的专业运维审计系统。

使用Python / Django 进行开发，遵循 Web 2.0 规范，配备了业界领先的 Web Terminal 解决方案，交互界面美观、用户体验好。

Jumpserver 采纳分布式架构, 支持多机房跨区域部署, 中心节点提供 API, 各机房部署登录节点, 可横向扩展、无并发访问限制。
Jumpserver 现已支持管理 SSH、 Telnet、 RDP、 VNC 协议资产。

我们这里主要采用docke版本进行安装，达到快速安装的效果，其他安装，见官网[jumpserver](https://jumpserver.readthedocs.io/zh/master/step_by_step.html).

## 2、安装前准备

关闭防火墙与禁止防火墙自动启动：

```
systemctl stop firewalld.service
systemctl disable firewalld.service
```

关闭selinux : 

```
setenforce 0
```


禁止selinux启动：vim /etc/selinux/config

```
SELINUX=disabled
```

## 3、安装docker

安装依赖

```
yum install -y yum-utils device-mapper-persistent-data lvm2
```

添加软件源

```
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
```

安装docker-ce

```
yum clean all
yum makecache fast
yum -y install docker-ce
```

使用镜像阿里云加速

```
mkdir -p /etc/docker
tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://s3w3uu4l.mirror.aliyuncs.com"]
}
EOF
```

启动服务
systemctl start docker

查看安装版本
docker version

## 4、安装redis

```
docker run --name redis \
 	-p $RD_PORT:6379 \
	-d --rm \
	-v /data/redis/data:/data \
	redis:3.2 \
	--appendonly yes \
	--requirepass "jumpserver2020"
```

## 5、安装mysql

mysql版本选择大于5.5，小于8.0,数据库编码要求 uft8

```
docker run -p 3306:3306 \
	--name mysql --rm \
	-v /data/mysql/conf:/etc/mysql/conf.d \
	-v /data/mysql/data:/var/lib/mysql \
	-e MYSQL_ROOT_PASSWORD=jumpserver2020 \
	-e MYSQL_USER=jumpserver \
    -e MYSQL_PASSWORD=jumpserver2020 \
	-e MYSQL_DATABASE=jumpserver \
	-e MYSQL_HOST=10.0.0.125 \
	-d mysql:5.7.20 \
	--default-authentication-plugin=mysql_native_password \
	--character-set-server=utf8mb4 \
	--collation-server=utf8mb4_unicode_ci
```

说明：

在运行MySQL容器时可以指定的环境参数有

```
    MYSQL_ROOT_PASSWORD ： root用户的密码，这里设置的初始化密码为`123456`；
    MYSQL_DATABASE ： 运行时需要创建的数据库名称；
    MYSQL_USER ： 运行时需要创建用户名，与MYSQL_PASSWORD一起使用；
    MYSQL_PASSWORD ： 运行时需要创建的用户名对应的密码，与MYSQL_USER一起使用；
    MYSQL_ALLOW_EMPTY_PASSWORD ： 是否允许root用户的密码为空，该参数对应的值为:yes；
    MYSQL_RANDOM_ROOT_PASSWORD：为root用户生成随机密码；
    MYSQL_ONETIME_PASSWORD ： 设置root用户的密码必须在第一次登陆时修改（只对5.6以上的版本支持）。
    MYSQL_ROOT_PASSWORD 和 MYSQL_RANDOM_ROOT_PASSWORD 两者必须有且只有一个。
```

## 6、安装jumpserver

生成随机加密秘钥, 勿外泄

```
if [ "$SECRET_KEY" = "" ]; then 
	SECRET_KEY=`cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 50`
	echo "SECRET_KEY=$SECRET_KEY" >> ~/.bashrc; echo $SECRET_KEY
else 
	echo $SECRET_KEY
fi
if [ "$BOOTSTRAP_TOKEN" = "" ]; then 
	BOOTSTRAP_TOKEN=`cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 16` 
	echo "BOOTSTRAP_TOKEN=$BOOTSTRAP_TOKEN" >> ~/.bashrc
	echo $BOOTSTRAP_TOKEN
else 
	echo $BOOTSTRAP_TOKEN
fi
```

安装jumpserver

```
$ docker run --name jumpserver -d \
    -v /data/jumpserver:/opt/jumpserver/data/media \
    -p 80:80 \
    -p 2222:2222 \
    -e SECRET_KEY=xxxxxx \
    -e BOOTSTRAP_TOKEN=xxx \
    -e DB_HOST=10.0.0.125 \
    -e DB_PORT=3306 \
    -e DB_USER=root \
    -e DB_PASSWORD=jumpserver2020 \
    -e DB_NAME=jumpserver \
    -e REDIS_HOST=10.0.0.125 \
    -e REDIS_PORT=6379 \
    -e REDIS_PASSWORD=jumpserver2020 \
    jumpserver/jms_all:latest
```

到此，jumpserver docker化完成，可以通过web页面，默认用户与密码是admin,admin,开始享受jumpserver之旅！

## 7、密码管理

当我们管理密码忘记了或者重置管理员密码，对于非docker化。只需要以下操作即可

```
admin_passwd=`cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 14`
source /data/jump/py3/bin/activate
cd /data/jump/jumpserver/apps
python manage.py changepassword  <user_name>
# 新建超级用户的命令如下命令
python manage.py createsuperuser --username=user --email=user@domain.com
```

而docker化，则需要进入到容器内进行修改

```
docker exec -it jumpserver /bin/bash
source py3/bin/activate
cd jumpserver/apps
python manage.py changepassword  <user_name>
# 新建超级用户的命令如下命令
python manage.py createsuperuser --username=user --email=user@domain.com
```

## 8、自动化部署

需要部署好docker，以及相应优化

```
cat << 'EOF' >jumpserver_install.sh
#!/bin/bash
#数据库版本推荐使用大于5.5小于8.0
JP_VERSION=latest
DB_VERSION=5.7.29
RD_VERSION=latest
DB_NAME=jumpserver
DB_USER=jumpserver
DB_PORT=3306
RD_PORT=6379
WEB_PORT=80
SSH_PORT=2222
JP_WORK_DIR=/data/jumpserver/$JP_VERSION
DB_WORK_DIR=/data/mysql/$DB_VERSION
RD_WORK_DIR=/data/redis/$RD_VERSION

kk (){
grep -w $1 ~/.bashrc &>/dev/null
if [ $? -ne 0 ];then
    nb=`cat /dev/urandom|tr -dc A-Za-z0-9|head -c $2`
    echo "$1" >> ~/.bashrc
    sed -ri "s#($1)#\1=$nb#g" ~/.bashrc
fi
}

kk SECRET_KEY 50
kk BOOTSTRAP_TOKEN 16
kk DB_PASSWORD 24
kk REDIS_PASSWORD 20

source ~/.bashrc

grep -w Server_IP ~/.bashrc &>/dev/null
if [ $? -ne 0 ];then 
    Server_IP=`ip a s eth0|awk -F'[ /]+' 'NR==3{print $3}'`
    echo "Server_IP=$Server_IP" >>~/.bashrc
fi

#redis
docker stop redis
docker run --name redis \
 	-p $RD_PORT:6379 \
	-d --rm \
	-v $RD_WORK_DIR/data:/data \
	redis:$RD_VERSION \
	--appendonly yes \
	--requirepass "$REDIS_PASSWORD" 

#mysql
docker stop mysql
docker run -p $DB_PORT:3306 \
	--name mysql --rm \
	-v $DB_WORK_DIR/conf:/etc/mysql/conf.d \
	-v $DB_WORK_DIR/data:/var/lib/mysql \
	-e MYSQL_ROOT_PASSWORD=$DB_PASSWORD \
	-e MYSQL_USER=$DB_USER \
    -e MYSQL_PASSWORD=$DB_PASSWORD \
	-e MYSQL_DATABASE=$DB_NAME \
	-e MYSQL_HOST=$Server_IP \
	-d mysql:$DB_VERSION \
	--default-authentication-plugin=mysql_native_password \
	--character-set-server=utf8mb4 \
	--collation-server=utf8mb4_unicode_ci

#jumpserver
docker stop jumpserver &>/dev/null
sleep 5s
docker run --name jumpserver -d --rm\
    -v $JP_WORK_DIR:/opt/jumpserver/data/media \
    -p $WEB_PORT:80 \
    -p $SSH_PORT:2222 \
    -e SECRET_KEY=$SECRET_KEY \
    -e BOOTSTRAP_TOKEN=$BOOTSTRAP_TOKEN \
    -e DB_HOST=$Server_IP \
    -e DB_PORT=$DB_PORT \
    -e DB_USER=$DB_USER \
    -e DB_PASSWORD=$DB_PASSWORD \
    -e DB_NAME=$DB_NAME \
    -e REDIS_HOST=$Server_IP \
    -e REDIS_PORT=$RD_PORT \
    -e REDIS_PASSWORD=$REDIS_PASSWORD \
    jumpserver/jms_all:$JP_VERSION
EOF
```

