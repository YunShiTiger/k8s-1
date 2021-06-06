## gitlib是什么？

Gitlab是一个用Ruby on Rails开发的开源项目管理程序，可以通过WEB界面进行访问公开的或者私人项目。它和Github有类似的功能，能够浏览源代码，管理缺陷和注释。

部署方式：

[gitlab]( https://packages.gitlab.com/gitlab/gitlab-ce/ )的安装方式有两种,一种是容器化安装,另外一种是yum安装,

### yum部署gitlab

安装依赖

```bash
yum install curl openssh-server openssh-clients
policycoreutils-python postfix -y
systemctl enable postfix 
systemctl start postfix
```

添加gitlab-ce源,并安装

```bash
cat<< EOF >/etc/yum.repos.d/gitlab-ce.repo
[gitlab-ce]
name=gitlab-ce
baseurl=http://mirrors.tuna.tsinghua.edu.cn/gitlab-ce/yum/el7
repo_gpgcheck=0
gpgcheck=0
enabled=1
gpgkey=https://packages.gitlab.com/gpg.key
EOF
```

更新缓存，查看版本

```bash
yum makecache
yum list gitlab-ce --showduplicates
```

安装特定版本

```bash
yum install gitlab-ce-12.4.2-ce.0.el7 -y
```

修改配置

vim /etc/gitlab/gitlab.rb

```bash
external_url -> 服务器http://IP:端口
gitlab_rails['gitlab_shell_ssh_port'] = 2222
```

修改配置后,需要重载配置

```bash
gitlab-ctl reconfigure
```

启动

```bash
gitlab-ctl restart
```

GitLab试用

1. 打开首页

地址：http://git.wzxmt.com.cn:8070

2. 设置管理员密码

首先根据提示输入管理员密码，这个密码是管理员用户的密码。对应的用户名是root，用于以管理员身份登录Gitlab。

3. 创建账号

设置好密码后去注册一个普通账号

4. 创建项目

注册成功后会跳到首页，我们创建一个项目，名字大家随意

5. 添加ssh key

项目建好了，我们加一个ssh key，以后本地pull/push就简单啦

首先去到添加ssh key的页面

然后拿到我们的sshkey 贴到框框里就行啦 怎么拿到呢？看下面：

```bash
#先看看是不是已经有啦，如果有内容就直接copy贴过去就行啦
 cat ~/.ssh/id_rsa.pub

#如果上一步没有这个文件 我们就创建一个，运行下面命令(邮箱改成自己的哦），一路回车就好了
 ssh-keygen -t rsa -C "wzxmt@163.com"
 cat ~/.ssh/id_rsa.pub
```

6. 测试一下

```bash
Command line instructions
You can also upload existing files from your computer using the instructions below.

Git global setup
git config --global user.name "wzxmt"
git config --global user.email "wzxmt@163.com"

Create a new repository
git clone git@git.wzxmt.com.cn:wzxmt/microservice.git
cd microservice
touch README.md
git add README.md
git commit -m "add README"
git push -u origin master

Push an existing folder
cd existing_folder
git init
git remote add origin git@git.wzxmt.com.cn:wzxmt/microservice.git
git add .
git commit -m "Initial commit"
git push -u origin master

Push an existing Git repository
cd existing_repo
git remote rename origin old-origin
git remote add origin git@git.wzxmt.com.cn:wzxmt/microservice.git
git push -u origin --all
git push -u origin --tags
```

去gitlab上看看我们新推送的项目.

分支说明

- master主分支，有且只有一个
- release线上分支，一般为线上版本，线上版本发布后，会将release分支合并到master
- develop 开发分支，通常给测试部署环境或者打包的分支，每个人在自己的分支上开发完成后，向develop分支合并
- feature 通常为一个功能分支或者个人分支，一般有很多个，通常合并完成后会删除

### docker部署gitlab

```bash
cat << 'EOF' > gitlab_start.sh
#!/bin/bash
HOST_NAME=git.wzxmt.com                #可以写域名(注意这个是变量以供下面${HOST_NAME}使用）
GITLAB_DIR=/data/gitlab            #GitLab工作目录(注意这个是变量以供下面${GITLAB_DIR}使用）
docker stop gitlab
docker run -d --rm \
    --hostname ${HOST_NAME} \
    -p 9443:443 -p 9999:80 -p 2222:22 \
    --name gitlab \
    -v ${GITLAB_DIR}/config:/etc/gitlab \
    -v ${GITLAB_DIR}/logs:/var/log/gitlab \
    -v ${GITLAB_DIR}/data:/var/opt/gitlab \
    gitlab/gitlab-ce:latest
EOF
```

运行start.sh 启动gitlab

```bash
sh gitlab_start.sh
```

配置环境

修改ssh端口(如果主机端口使用的不是22端口）

修改文件：${GITLAB_DIR}/config/gitlab.rb 找到这一行：# gitlab_rails['gitlab_shell_ssh_port'] = 22 把22修改为你的宿主机端口(这里是2222）。然后将注释去掉。

```bash
GITLAB_DIR=/data/gitlab
sed -ri.bak "s/^#(.*)22$/\12222/g" ${GITLAB_DIR}/config/gitlab.rb
```

重新启动容器

```bash
 sh gitlab_start.sh
```

### k8s部署gitlab

#### 1、集群初始化

拉取镜像

```bash
#gitlab
docker pull sameersbn/gitlab:11.5.1
docker tag sameersbn/gitlab:11.5.1 harbor.wzxmt.com/infra/gitlab:11.5.1
docker push harbor.wzxmt.com/infra/gitlab:11.5.1
#postgresql
docker pull sameersbn/postgresql:10
docker tag sameersbn/postgresql:10 harbor.wzxmt.com/infra/sameersbn/postgresql:10
docker push harbor.wzxmt.com/infra/postgresql:10
#sameersbn/redis
docker pull sameersbn/sameersbn/redis
docker tag sameersbn/sameersbn/redis harbor.wzxmt.com/infra/sameersbn/redis:lates
docker push harbor.wzxmt.com/infra/sameersbn/redis:lates
```

创建目录

```bash
mkdir -p gitlab /data/nfs-volume/gitlab-data && cd gitlab
```

pv

```yaml
cat << EOF >pv.yaml 
apiVersion: v1
kind: PersistentVolume
metadata:
  name: gitlab-data-pv
spec:
  capacity:
    storage: 20Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs
  nfs:
    path: /data/nfs-volume/gitlab-data
    server: 10.0.0.20
EOF
```

pvc

```yaml
cat << 'EOF' >pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitlab-data-pvc
  namespace: infra
spec:
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  resources:
    requests:
      storage: 20Gi
  storageClassName: nfs
EOF
```

#### 2、部署redis

```yaml
cat << 'EOF' >dp.yaml
EOF
```

Service

```yaml
cat << 'EOF' >svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: public-service
  labels:
    name: redis
spec:
  ports:
    - name: redis
      port: 6379
      targetPort: redis
  selector:
    name: redis
EOF
```

#### 3、部署postgresql

dp

```yaml
cat << 'EOF' >dp.yaml
EOF
```

svc

```yaml
cat << 'EOF' >svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  namespace: public-service
  labels:
    name: postgresql
spec:
  ports:
    - name: postgres
      port: 5432
      targetPort: postgres
  selector:
    name: postgresql
EOF
```

#### 4、部署gitlab

dp

```yaml
cat << 'EOF' >dp.yamlEOF
```

svc

```yaml
cat << 'EOF' >svc.yamlapiVersion: v1kind: Servicemetadata:  name: gitlab  namespace: public-service  labels:    name: gitlabspec:  type: ClusterIP  ports:    - name: http      port: 80      targetPort: http    - name: ssh      port: 22      targetPort: ssh  selector:    name: gitlabEOF
```

ingress

```yaml
cat << 'EOF' >ingress.yamlapiVersion: traefik.containo.us/v1alpha1kind: IngressRoutemetadata:  name: gitlab  namespace: infraspec:  entryPoints:    - web  routes:  - match: Host(`gitlab.wzxmt.com`) && PathPrefix(`/`)    kind: Rule    services:    - name: nexus-svc      port: 8083EOF
```

访问http://gitlab.wzxmt.com