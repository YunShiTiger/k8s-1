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