#!/bin/bash
#################################################
#    File Name: docker_install
#       Author: lxw
#         Mail: 1451343603@qq.com
#     Function:
# Created Time: Thu 07 Nov 2019 02:31:35 PM CST
#################################################
DATE=`date +%Y%m%d`
yum_repo (){
cd /etc/yum.repos.d
\mv CentOS-Base.repo CentOS-Base.repo.bak
\mv epel.repo  epel.repo.bak
curl https://mirrors.aliyun.com/repo/Centos-7.repo -o CentOS-Base.repo 
curl https://mirrors.aliyun.com/repo/epel-7.repo -o epel.repo
yum makecache fast
}

docker_rely (){
yum install -y yum-utils device-mapper-persistent-data lvm2
}

docker_repo (){
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum makecache fast
rpm --import https://mirrors.aliyun.com/docker-ce/linux/centos/gpg
}

docker_version_check (){
version=`docker version|grep 'Version'|awk 'NR==2{print $2}'`
if [ ! -z $version ];then
  echo "docker_oldversion is $version"
  read -p "是否要卸载docker_$version,安装新版本(y/n)：" n
  case $n in
     Y|y)
     docker_remove
	 read -p "是否继续安装docker(y/n)：" m
	 case $m in
		 N|n)
			 exit 1
	 esac
     ;;
     *)
     exit 1
  esac
else
   echo "没有安装docker"
fi
}

docker_remove (){
yum remove -y docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-selinux \
                  docker-engine-selinux \
                  docker-engine
rm -rf /etc/systemd/system/docker.service.d
rm -rf /var/lib/docker
rm -rf /var/run/docker
}

docker_version (){
clear all
yum list docker-ce.x86_64  --showduplicates |awk 'NR>6{print $2}'|sed -r 's#3:##g'
}

docker_install_env (){
chose=`yum list docker-ce.x86_64  --showduplicates |awk 'NR>6{print $2}'|tr "\n" "|"|sed -r 's#(.*)\|#\1#g;s#3:##g'`
cat << 'EOF' >./docker_version.sh
#!/bin/bash
docker_install_version (){
docker_version
read -p "请输入要安装的版本号：" m
case $m in
    yum install -y docker-ce-$m
    ;;
    *)
    exit 1
esac
}
EOF
sed -i "/case/a $chose\)" ./docker_version.sh
source ./docker_version.sh
rm -f ./docker_version.sh
}

speed_docker (){
rm -f /etc/docker/daemon.json 
mkdir -p /etc/docker
tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://s3w3uu4l.mirror.aliyuncs.com"]
}
EOF
}

docker_forward (){
sed -i.${DATE} '/ExecStart/a\ExecStartPost=/sbin/iptables -I FORWARD -s 0.0.0.0/0 -j ACCEPT' /lib/systemd/system/docker.service
}

docer_systemd (){
sed -ri.${DATE} "s#(.*)(.*)}#\1\2,$1}#g" /etc/docker/daemon.json
}

docker_start (){
#设置 docker 开机服务启动
systemctl enable docker.service 
#重载配置
systemctl daemon-reload
#立即启动 docker 服务re
systemctl restart docker.service
}

echo "docker版本检测"
docker_version_check
echo "配置yum源"
yum_repo
echo "安装docker依赖"
docker_rely
echo "配置docker源"
docker_repo
#docker_env
docker_install_env
#选择版本进行安装
docker_install_version

read -p "是否使用加速(y/n)：" m
case $m in
     Y|y)
     speed_docker
esac

read -p "是否system管理docker(y/n)：" n
case $n in
     Y|y)
     docer_systemd '"exec-opts": ["native.cgroupdriver=systemd"]'
esac

read -p "是否配置所有ip的数据包转发(y/n)" n
case $n in
     Y|y)
     docker_forward
esac

echo "启动docker"
docker_start
#docker版本
docker version
exit $?
