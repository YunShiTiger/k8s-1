#!/bin/bash
pas=H5SFopetzElIhTnOKpbF
[ -f /etc/yum.repos.d/epel.repo ]||echo "正在安装epel源..."
wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo &>/dev/null
rpm -q sshpass &>/dev/null ||echo "正在安装sshpass..."
yum -y install sshpass &>/dev/null
#创建密钥对
echo "正在创建密钥对...."
[ -d ~/.ss ] || mkdir ~/.ssh &>/dev/null;chmod 700 ~/.ssh
rm -fr ~/.ssh/*
ssh-keygen -t dsa -f "/root/.ssh/id_dsa" -N "" -q && echo "创建密钥对成功" || exit
#秘钥分发
echo "正在分发密钥对"
for ip in `cat iplist.txt`
do
  echo "-----秘钥分发到${ip}----"
  sshpass -p${pas} ssh-copy-id -f -i /root/.ssh/id_dsa.pub ${ip} -p 22 -o StrictHostKeyChecking=no &>/dev/null
  if [ $? -eq 0 ];then
    echo "----秘钥分发到$ip成功----"
  else
    echo "----秘钥分发到$ip失败----"
  fi
done
