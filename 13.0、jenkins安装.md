## 1. jenkins安装

[jenkins]( https://jenkins.io/zh/download/ ) 项目产生两个发行线, 长期支持版本 (LTS) 和每周更新版本。 ` .war` 文件, 原生包, 安装程序, 和 Docker 容器的形式分发 ;这里使用tomcat部署jenkins

#### 1.1安装jdk

```bash
https://www.oracle.com/technetwork/java/javase/downloads/jdk8-downloads-2133151.html )
```

安装包版本：jdk-8u25-linux-x64.tar.gz

```bash
tar xf jdk-8u25-linux-x64.tar.gz -C /opt/
cd /opt/
ln -s jdk1.8.0_211 jdk
```

添加环境变量

```bash
sed -i.ori '$a export JAVA_HOME=/opt/jdk\nexport PATH=$JAVA_HOME/bin:$JAVA_HOME/jre/bin:$PATH\nexport CLASSPATH=.:$JAVA_HOME/lib:$JAVA_HOME/jre/lib:$JAVA_HOME/lib/tools.jar' /etc/profile
```

加载环境变量

```
source /etc/profile
```

查看版本

```
java -version
```

#### 1.2安装maven

```bash
https://maven.apache.org/
```

下载maven

```bash
wget http://us.mirrors.quenda.co/apache/maven/maven-3/3.6.2/binaries/apache-maven-3.6.2-bin.tar.gz
```

解压到指定位置

```bash
tar xf apache-maven-3.6.2-bin.tar.gz
ln -s /opt/apache-maven-3.6.2 /opt/maven
echo 'export PATH=/opt/maven/bin:$PATH' >>/etc/profile
source /etc/profile
```

#### 1.3安装tomcat,下载到主机

```bash
http://tomcat.apache.org/ 
```

下载tomcat

```bash
wget http://mirrors.tuna.tsinghua.edu.cn/apache/tomcat/tomcat-8/v8.5.47/bin/apache-tomcat-8.5.47.zip
```

解压到指定位置

```bash
unzip -d /data/tomcat
cd /data/tomcat/webapps
rm -fr *
```

下载jenkins.war包

```bash
wget http://mirrors.jenkins.io/war-stable/latest/jenkins.war
```

下载好了,我们进入到tomcat目录下的bin目录,启动服务

```bash
chmod +x *
sh startup.sh
```

默认jenkins数据路径会在/root/.Jenkins下

#### 1.4 修改默认数据位置

 使用Web容器容器管理工具设置JENKINS_HOME环境参数.

在启动Web容器之前设置JENKINS_HOME

```bash
cat << EOF >>/etc/profile
export JENKINS_HOME=/data/jenkins
export TOMCAT_HOME=/data/tomcat
EOF
source /etc/profile 
```

 打开tomcat的bin目录，编辑catalina.sh文件,添加(export JENKINS_HOME=/data/)

```bash
sed -i.bak '/# OS/a export JENKINS_HOME=/data/jenkins' ${TOMCAT_HOME}/bin/catalina.sh
```

#### 1.5 Jenkins安装插件加速

 其配置在Jenkins的工作目录中下的updates 的default.json文件中,主要实现方法是替换所有插件下载的url与 连接测试url 

```bash
WORK_DIR=/data/jenkins
#优化插件下载与连接测试url
sed -i.bak 's#http://updates.jenkins-ci.org/download#https://mirrors.tuna.tsinghua.edu.cn/jenkins#g;s#http://www.google.com#https://www.baidu.com#g' ${WORK_DIR}/updates/default.json
```

 #### 1.6 修改配置,域名+端口访问

需要修改成域名 +端口访问方式,要不然后面与gitlab 进行webhook时会报错! 

修改tomcat目录config下的server.xml,需要在<Host **** >后面添加一行

```bash
<Context path="" docBase="/data/tomcat/webapps/jenkins" 
    debug="0" reloadable="false" crossContext="true"/>
```

所有修改配置都是在停服务下进行!重启后,可以进入到我们的web界面:[jenkins](10.0.0.37:8080)

当然了,也可以通过  nohup java -jar jenkins.war --httpPort=8080 & 来部署.

#### 1.7 docker部署jenkins

```bash
cat<< 'EOF' >jenkins.sh
#!/bin/bash
WORK_DIR=/data/jenkins
read -p "pls in put port: " m
while [ -z $m ]
do
  read -p "pls in put port: " m
done
mkdir -p ${WORK_DIR}/home
docker stop jenkins &>/dev/null
docker rm jenkins &>/dev/null
jenkins_start (){
docker run -d -u root \
  --name jenkins \
  -p $m:8080 -h jenkins\
  -v ${WORK_DIR}/home:/root/ \
  -v ${WORK_DIR}/:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc/localtime:/etc/localtime \
  jenkins/jenkins:latest
}
jenkins_start
sleep 60s
#优化插件下载与连接测试url
sed -i.bak 's#http://updates.jenkins-ci.org/download#https://mirrors.tuna.tsinghua.edu.cn/jenkins#g;s#http://www.google.com#https://www.baidu.com#g' ${WORK_DIR}/updates/default.json
passwd=`cat ${WORK_DIR}/secrets/initialAdminPassword`
echo "管理员密码: $passwd"
#重启jenkins
docker restart jenkins
EOF
```

启动jenkins

```bash
sh jenkins.sh 8080
```

然后可以访问wen页面[jenkins](jk.wzxmt.com.cn:8080)