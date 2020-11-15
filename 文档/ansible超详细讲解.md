# ansible超详细讲解，值得收藏

自动化执行的方式有很多种，最原始的就是shell脚本，但是显然它不能满足我们的需求。常见自动化配置管理工具有很多种，slatstack和ansible是比较流行的两种，而且它们都是用python开发的，但是相对来讲ansible的优势更加明显，主要是因为它拥有大量的模块和插件，而且你在GitHub和gitee上也可以找到很多别人写好的编排剧本，基本拿过来就可以使用了。

![ansible超详细讲解，值得收藏](https://p3-tt.byteimg.com/origin/pgc-image/02a45f9db4fc4d68bda0c2d9cf0692cb?from=pc)



# Ansible简介

尽管我认为当你看这篇文章的时候，可能对ansible有了至少一丁丁了解，但是简单的介绍还是要说一下的。Ansible是一个开源配置管理工具，可以使用它来自动化任务，部署应用程序实现IT基础架构。Ansible可以用来自动化日常任务，比如，服务器的初始化配置、安全基线配置、更新和打补丁系统，安装软件包等。

# Ansible安装

- Centos

```bash
wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
yum clean all
yum makecache
yum install -y ansible
```

- Ubuntu

```bash
apt-get install software-properties-common
apt-add-repository ppa:ansible/ansible
apt-get update
apt-get install ansible
```

- pip安装

```bash
pip install ansible
```

pip这种方式是最方便的，毕竟我们一般都安装了Python，但是可能会有一个问题，安装完以后，我们找不到配置文件，使用ansible --version查看发现config file是none，导致我们没法正常使用，这是为什么呢？因为ansible加载配置文件的路径是有顺序的。

# **ansible.cfg文件加载顺序**

ansible.cfg文件作为配置文件，ansible会在多个路径下进行读取，读取的顺序如下：

- ANSIBLE_CONFIG：环境变量
- ansible.cfg：当前执行目录下
- .ansible.cfg：~/.ansible.cfg
- /etc/ansible/ansible.cfg

所以推荐使用方式是创建一个工程目录，将所有的配置文件都放置在此目录下，这样更方便移植。在ansible.cfg中有如下内容：

```yaml
[defaults]
inventory = ./hosts
host_key_checking = False
```

所以我们使用pip安装后，在主机上通过find命令查找到ansible.cfg，默认会安装到python目录下，将其复制到当前执行目录即可。

配置文件有三个：

1. ansible.cfg --ansible的配置文件，一般我们都使用默认配置，只需要改增加一个host_key_checking=False，不使用指纹验证。指纹验证就是当我们在一台Linux机器上ssh登录另一台Linux时，第一次连接会让我们输入Yes/No
2. hosts --主机文件清单
3. roles --一个配置角色的文件夹，默认里面是空的

# 配置Ansible主机清单

主机清单通常用来定义要管理的主机信息，包括IP、用户、密码以及SSH key配置。可以分组配置，组与组之间可以配置包含关系，使我们可以按组分配操作主机。配置文件的路径为：/etc/ansible/hosts

# **基于密码的方式连接**

vim /etc/ansible/hosts

```bash
# 方式一
[web]
10.0.0.31 ansible_ssh_user=root ansible_ssh_pass=123456
10.0.0.32 ansible_ssh_user=root ansible_ssh_pass=123456
10.0.0.33 ansible_ssh_user=root ansible_ssh_pass=123456

# 方式二
[web]
10.0.0.31
10.0.0.32
10.0.0.33

[web:vars]
ansible_ssh_user=root ansible_ssh_pass=123456

# 方式三
[web]
10.0.0.31
10.0.0.32
10.0.0.33

# 在/etc/ansible目录下创建目录group_vars，然后再创建文件web.yml，以组名命名的yml文件
vim /etc/ansible/group_vars/web.yml

# 内容如下
ansible_ssh_user: root
ansible_ssh_pass: 123456
```

测试命令

```bash
[root@manage ~]# ansible web -m ping

10.0.0.31 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    }, 
    "changed": false, 
    "ping": "pong"
}
```

# **基于SSH key方式连接**

以下命令均在ansible主机执行，无需到被管理机器操作

```bash
# 生成ssh key，一路回车，默认生成在/root/.ssh目录下id_rsa和id_rsa.pub
ssh-keygen

# 将公钥拷贝到目标主机
ssh-copy-id root@10.0.0.32

# 执行以上语句，并输入密码，会在目标主机生成一个文件/root/.ssh/authorized_keys
# 之后再连接目标主机就不需要密码了
```

# ad-hoc命令

ad-hoc是临时命令，就像我们执行的shell命令一样，执行完即结束，ad-hoc模式的命令格式如下：

```
ansible web -m command -a 'df -h'
```

命令解释：

- ansible：命令
- web：主机名/IP/分组
- -m：指定模块（默认是command，所以可以把-m command这个去掉）
- command：模块名称
- -a：模块参数
- 'df -h'：参数值

执行命令返回的结果颜色代表的含义：

绿色：被管理端没有被修改

黄色：被管理端发生变更

红色：执行出现故障

# 常用模块介绍

ansible官方存在大量的模块，我们使用ansible主要使用的也是因为它有大量的模块和插件，虽然模块很多，但是我们常用的模块就那么几种，下面介绍以下常用模块：

| 模块名         | 说明                                             |
| -------------- | ------------------------------------------------ |
| command(默认)  | 不支持管道过滤grep                               |
| shell          | 支持管道过滤grep                                 |
| script         | 不用把脚本复制到远程主机就可以在远程主机执行脚本 |
| yum            | 安装软件                                         |
| yum_repository | 配置yum源                                        |
| copy           | 拷贝文件到远程主机                               |
| file           | 在远程主机创建目录或者文件                       |
| service        | 启动或者停止服务                                 |
| mount          | 挂载设备                                         |
| cron           | 执行定时任务                                     |
| firewalld      | 防火墙配置                                       |
| get_url        | 下载软件或者访问网页                             |
| git            | 执行git命令                                      |

```bash
ansible test -m ping 测试

chdir: 表示先进行切换远程主机路径信息,然后再还行相应的命令 
ansible test -m command -a "chdir=/tmp pwd"
	
creates: 表示判断文件信息是否存在,如果存在就跳过后续命令的执行过程
ansible test -m command -a "creates=/etc/hosts ls /etc/hosts"

removes: 表示判断文件信息是否存在,如果存在就执行后续命令
ansible test -m shell -a "removes=/etc/hosts ls /etc/hosts"

说明: shell模块支持识别一些特殊符号信息: 变量$HOME和操作，例如"<"，">"，"|"，";"和"&"可以正常使用
	
shell模块执行脚本: 远程主机要有脚本
ansible test -m shell -a "/bin/sh /server/scripts/ansible_test.sh"

script模块执行脚本:执行一个脚本的模块,在本地执行等价于在远程主机上执行
ansible	test -m script -a "/server/scripts/ansible_test.sh"

dest/src功能说明: 执行要复制的数据源信息和目标信息
ansible test -m copy -a "src=/etc/hosts dest=/etc/"
    
owner/group:表示定义数据信息属主或属组
ansible test -m copy -a "src=/etc/hosts dest=/etc/hosts01.txt owner=oldboy group=oldboy"

mode:表示定义文件权限信息
ansible test -m copy -a "src=/etc/hosts dest=/etc/hosts02.txt owner=oldboy group=oldboy mode=600"

backup:备份文件参数
ansible test -m copy -a "src=/etc/hosts dest=/etc/ backup=yes"
    
content:编辑定义文件中的内容信息
ansible test -m copy -a "content=oldboy123 dest=/etc/rsync.password mode=600"
	
功能说明: 实现远程主机数据手工备份
ansible test -m copy -a "src=/etc/hosts dest=/opt/h01.txt remote_src=no" 本地—远程（默认）
ansible test -m copy -a "src=/etc/hosts dest=/opt/h02.txt remote_src=yes" 远程—远程
ansible test -m fetch -a "src=/etc/hosts dest=/opt/h02.txt" 将远程文件拉取到本地
file模块功能说明：修改文件属性信息; 可以创建文件信息 目录信息 或者链接文件信息
path:/dest/name 指定路径信息
state: 
directory: 创建目录	touch :创建文件		link：创建软连接	hard：创建硬连接

递归 recurse=yes
ansible test -m file -a "dest=/tmp/01/ owner=oldboy recurse=yes"
   
cron模块功能说明：可以
变量编辑定时任务信息	minute	hour	day	month	weekday:   
	
job: 执行的命令 
state=absent删除定时任务

创建定时任务
ansible test -m cron -a "name='date' minute=*/5 job='date'"

删除定时任务
ansible test -m cron -a "name='date' state=absent"

注释定时任务
ansible test -m cron -a "name='date' job='ntpdate' disabled=yes"

取消注释任务
ansible test -m cron -a "name='date' job='date' disabled=no"

service:指定运行状态
	enabled:是否开机自启  -->ture/false
	name:服务名称
	state：状态 started 、stoped、restarted
yum: 安装程序包
	name:指明要安装的程序包，可以带上版本号
	state: present,latest表示安装，absent表示卸载 remove 移除
        – config_file：yum的配置文件 （optional） 
        – disable_gpg_check：关闭gpg_check （optional） 
        – disablerepo：不启用某个源 （optional） 
        – enablerepo：启用某个源（optional） 
synchronize模块
– 使用rsync同步文件，将主控方目录推送到指定节点的目录下，其参数如下： 
– delete： 删除不存在的文件，delete=yes 使两边的内容一样（即以推送方为主），默认no 
– src： 要同步到目的地的源主机上的路径; 路径可以是绝对的或相对的。如果路径使用”/”来结尾，则只复制目录里的内容，如果没有使用”/”来结尾，则包含目录在内的整个内容全部复制 (可以是url)
– dest：目的地主机上将与源同步的路径; 路径可以是绝对的或相对的。 
– dest_port：默认目录主机上的端口 ，默认是22，走的ssh协议。 
– mode: push或pull，默认push，一般用于从本机向远程主机上传文件，pull 模式用于从远程主机上取文件。 
– rsync_opts：通过传递数组来指定其他rsync选项。

# 将控制机器上的src同步到远程主机上
- synchronize:
    src: some/relative/path
    dest: /some/absolute/path

# 同步传递额外的rsync选项
- synchronize:
    src: /tmp/helloworld
    dest: /var/www/helloworld
    rsync_opts:
      - "--no-motd"
      - "--exclude=.git"

setup：收集远程主机的facts信息
每个被管理节点在被管理命令之前，会将自己主机相关信息，如操作系统版本、IP地址等

filter 过滤
ansible test -m setup -a "filter=ansible_all_ipv4_addresses"

get_url模块
– url_password、url_username：主要用于需要用户名密码进行验证的情况 
dest 下载到目标机路径
ansible test -m get_url -a "url=http://nginx.org/download/nginx-1.14.0.tar.gz dest=/tmp/" 下载到目标机
ansible test -m git -a "repo=https:github.com/iopsgrop/imoocc dest=/tmp/imoocc version=HEAD"

lineinfile: path=/php/etc/php-fpm.conf regexp=";pid" line="pid"  #修改文件(相当于sed 单行替换）

user: name=www state=present shell=/sbin/nologin createhome=no uid=666

unarchive：  （zip  gtar）
– copy：在解压文件之前，是否先将文件复制到远程主机，默认为yes。若为no，则要求目标主机上压缩包必须存在。 
– creates：指定一个文件名，当该文件存在时，则解压指令不执行 
– dest：远程主机上的一个路径，即文件解压的绝对路径。 
– group：解压后的目录或文件的属组 
– list_files：如果为yes，则会列出压缩包里的文件，默认为no，2.0版本新增的选项 
– mode：解压后文件的权限 
– src：如果copy为yes，则需要指定压缩文件的源路径 
– owner：解压后文件或目录的属主
ansible test -m unarchive -a "src=/root/libiconv-1.14.tar.gz dest=/root/" 本地文件解压到远程目录
ansible test -m unarchive -a "src=http://nginx.org/download/nginx-1.14.1.tar.gz dest=/root/" 将文件下载到远程并解压
mount模块常用参数
	fstype 指定挂载文件类型 -t nfs == fstype=nfs
	opts   设定挂载的参数选项信息 -o ro  == opts=ro
	path   挂载点路径          path=/mnt
	src	要被挂载的目录信息  src=172.16.1.31:/data
	state   unmounted  加载/etc/fstab文件 实现卸载
		absent     在fstab文件中删除挂载配置
		present    在fstab文件中添加挂载配置
		mounted	   1.将挂载信息添加到/etc/fstab文件中 2.加载配置文件挂载

ansible 172.16.1.8 -m hostname -a "name=web01" 修改主机名

ansible 172.16.1.8 -m selinux -a "state=disabled" 修改seLinux

- name: *
  shell:   *
  async: 2  //最长等待10秒返回
  poll: 0    //值为0表示无需等待该任务返回
nsible 有时候要执行等待时间很长的操作,  这个操作可能要持续很长时间, 

设置超过ssh的timeout. 这时候可以在step中指定async 和 poll 来实现异步操作

async 表示这个step的最长等待时长,  如果设置为0, 表示一直等待下去直到动作完成.

poll 表示检查step操作结果的间隔时长.

wait_for模块
connect_timeout 在下一个事情发生前等待链接的时间，单位是秒
delay 延时，在做下一个事情前延时多少秒
path   当一个文件存在于文件系统中，下一步才继续
state(present/started/stopped/absent) [对象是端口的时候start状态会确保端口是打开的，stoped状态会确认端口是关闭的;对象是文件的时候，present或者started会确认文件是存在的，而absent会确认文件是不存在的。]
案例：
10秒后在当前主机开始检查8000端口，直到端口启动后返回
- wait_for: port=8000 delay=10

# 检查path=/tmp/foo直到文件存在后继续
- wait_for: path=/tmp/foo

# 直到/var/lock/file.lock移除后继续
- wait_for: path=/var/lock/file.lock state=absent

# 直到/proc/3466/status移除后继续
- wait_for: path=/proc/3466/status state=absent
```

以上是部分常用模块的解释与示例，因为ansible的模块和参数很多，我们就不做详细解释了。但是这里要说一个非常非常重要的一点，以上全都是废话，任何一个模块，ansible都为我们提供了非常详细的解释文档，例如查看cron模块的用法，查询命令如下：

```bash
ansible-doc cron
```

如果想查询都有哪些模块，**ansible-doc -l > ansible.doc**，当然了，执行示例是按照ansible-playbook的方式显示的，但是我们稍微改一下就可以用ad-doc的方式执行了

# 报错处理

```
[WARNING]: provided hosts list is empty, only localhost is available. Note that the implicit localhost does not match 'all'
[WARNING]: Could not match supplied host pattern, ignoring: oldboy
```

这个问题一般是没有在ansible.cfg内指定主机清单文件导致的，配置正确的inventory路径即可，还可以通过在ansible命令后面加-i来指定。

# playbook

**Playbook** 与 **ad-hoc** 相比,是一种完全不同的运用ansible的方式，类似于saltstack的state状态文件。ad-hoc无法持久使用，playbook可以持久使用。playbook是由一个或多个play组成的列表，play的主要功能在于将事先归并为一组的主机装扮成事先通过ansible中的task定义好的角色。从根本上来讲，所谓的task无非是调用ansible的一个module。将多个play组织在一个playbook中，即可以让它们联合起来按事先编排的机制完成某一任务。

Playbook是通过yml语法进行编排的，使用起来非常简单，我们只需要知道一些基本的关键字就可以实现了。

- hosts：
- tasks：
- vars：
- templates：
- handlers：
- tags：

下面给一个简单的例子：

```
# httpd.yaml
- hosts: web  
  tasks:    
    - name: install httpd server      
      yum: name=httpd state=present          
    
    - name: configure httpd server      
      copy: src=httpd.conf dest=/etc/httpd/conf/httpd.conf          
     
    - name: configure httpd server      
      copy: src=index.html dest=/var/www/html/index.html          
        
    - name: service httpd server      
      service: name=httpd state=started enabled=yes
```

这是一个安装Apache、配置、启动的流程，我们看一下其中的关键字。

- hosts：需要执行的主机、组、IP
- tasks：执行的任务
- name：任务描述
- yum/copy/service：执行模块（上面我们介绍过的）

这就是最基础的Playbook的结构，也是一个Playbook所必备的结构，当然还有更多高级的操作，我们下面通过更多的示例来给大家讲解。

# **搭建nginx服务**

```
- hosts: web  
  vars:    
    hello: Ansible      
    
  tasks:    
    # 配置软件源    
    - name: Configure Yum Repo      
      yum_repository:         
        name: nginx        
        description: nginx repo        
        baseurl: http://nginx.org/packages/centos/7/$basearch/        
        gpgcheck: yes        
        enabled: yes    
        
    # 安装nginx        
    - name: Install Nginx      
      yum: name=ningx state=present        
   
    # 替换配置文件    
    - name: Configure Nginx      
      copy:         
        src: nginx.conf        
        dest: /etc/nginx/conf/nginx.conf            

    # 修改首页    
    - name: Change Home      
      copy:         
        content: "Hello {{hello}}"        
        dest: /var/www/html/index.html            

    # 启动nginx    
    - name: Start Nginx      
      service:        
        name: nginx        
        state: started
```

上面这个例子在模块使用时，我用了两种例子

**yum: name=nginx state=present**

```
copy:  
  src: nginx.conf  
  dest: /etc/nginx/conf/nginx.conf
```

这两种方式都是可以的，只是写法不同，希望不要有人被误导，另外在这里例子中我们还引入了下一个知识点-**变量**

# **Ansible中的变量**

# **为什么要使用变量？**

首先我们要明确为什么使用变量？变量这个词在编程当中经常用到，我们一直强调在编程中不要使用魔法数字，尽量使用宏或者变量代替，魔法数字一方面意义不够明确，另外一方面在修改的时候，要涉及到很多地方，会出现纰漏。那么在ansible中使用变量的意义也是一样的，**明确意义、方便修改**。

# **怎么定义变量和使用变量？**

- 在playbook文件中的hosts下使用vars进行定义

1. 在playbook文件中直接定义变量

```
- hosts: web 
  vars:   
    web_pack: httpd-2.4.6   
    ftp_pack: vsftpd    
    # - web_pack: httpd-2.4.6 与上面等同     
    
  tasks:   
    - name: Install {{pack_name}}     
      yum:       
        name:         
          - "{{web_pack}}"         
          - "{{ftp_pack}}"       
          state: present
```

1. 额外定义一个变量文件

如果是在多个文件中使用同样的变量，可以定义一个变量文件，在playbook中使用vars_files中引入即可

```
# vars.yml
web_pack: httpd-2.4.6
ftp_pack: vsftpd
- hosts: web 
  vars_files:   
    - ./vars.yml
```

- 在主机清单文件中进行定义

1. 在主机清单文件中定义

```
# hosts
[web]
192.168.143.122

[web:vars]
pack_name=httpd
# playbook中使用，可以直接使用，如果当前文件中搜索不到，就去主机清单中搜搜
- hosts: web 
  tasks:   
    - name: install {{pack_name}}     
      yum: name={{pack_name}} state=present
```

1. 单独定义group_vars和host_vars目录

group_vars是为组定义的变量目录，其下文件名为组名，例如group_vars/web，host_vars是为主机定义的变量目录，其下文件名为IP，例如host_vars/192.168.143.122。

**注意**：默认情况下，group_vars目录中文件名与hosts清单中的组名保持一致，因此在使用的时候，只对本组有效，其他组不能使用，但是系统还提供了一个特殊的组-all，在group_vars新建一个all文件，所有组都可以使用

```
# web文件
pack_name: httpd 
```

- 执行playbook时使用-e参数指定变量

```
ansible-playbook httpd.yml -e "pack_name=httpd" -e "hosts=web"
```

hosts变量通过-e传递是比较常见的，我们可以区分测试环境和生产环境，当然你也可以定义不同的文件来区分

# **ansible 变量的优先级**

上面我们介绍了多种变量的定义方式，那么如果在多个地方定义了相同的变量，优先会使用哪个呢？这就涉及到变量优先级的问题了。

- 通过执行命令传递的变量
- 在playbook中引入vars_files中的变量
- 在playbook中定义的vars变量
- 在host_vars中定义的变量
- 在group_vars中组名文件中定义的变量
- 在group_vars中all文件中定义的变量

# **ansible resister注册变量**

在我们使用ansible-playbook的时候，它的输出是固定的格式的，假如我们启动了httpd服务以后，想要看一下这个服务的状态，我们不能登录到目标主机去查看，那么ansible有什么方式可以查看吗？

```
- hosts: web  
  tasks:    
    - name: install httpd server      
      yum: name=httpd state=present          
       
    - name: service httpd server      
      service: name=httpd state=started enabled=yes          
        
    - name: check httpd state      
      shell: ps aux|grep httpd      
      register: httpd_status          
        
    - name: output httpd_status variable      
      debug:        
        msg: "{{httpd_status}}"
```

![ansible超详细讲解，值得收藏](https://p1-tt.byteimg.com/origin/pgc-image/8e79e70ef4b34cc8be006a90ff3b703d?from=pc)



上面是输出了所有的内容，如果需要输出部分内容，只要用**变量.属性**就行了，属性就是msg下的字典

# **ansible facts变量的意义**

![ansible超详细讲解，值得收藏](https://p6-tt.byteimg.com/origin/pgc-image/6652ad151e4c4784b95f4cfbe08bf3f6?from=pc)



这是我们安装Apache的打印，可以看到分为几个过程：PLAY、TASK、PLAY RECAP，在TASK的第一个打印我们看到是Gathering Facts，但是我们并没有添加这个任务，这是ansible自动为我们添加的，这个任务是做什么用的呢？我们在执行的过程中发现这一块执行时间还比较长。这个任务的主要作用是获取目标主机的信息，我们看一下都能获取哪些信息，可以通过以下语句打印：**ansible web -m setup**

![ansible超详细讲解，值得收藏](https://p1-tt.byteimg.com/origin/pgc-image/d111dc8ed184487f9f01c8cfb2b38b66?from=pc)



包括CUP、内存、硬盘、网络、主机名、绑定信息、系统版本信息等等，非常多的信息，这些信息都可以在playbook中当做变量使用。

```
- hosts: web  
  tasks:    
    - name: Query Host Info      
      debug:        
        msg: IP address is {{ansible_default_ipv4.address}} in hosts {{ansible_distribution}}
```

![ansible超详细讲解，值得收藏](https://p6-tt.byteimg.com/origin/pgc-image/a9802bdb832446f2a2f876731372f52c?from=pc)



那么这个可以在什么情况下使用呢？例如根据目标主机的CPU数，配置nginx并发进程数量，当然如果不使用，我们也可以关闭它。

```
- hosts: web  
  gather_facts: no    
  
  tasks:    
    - name: install httpd server      
      yum: name=httpd state=present          
        
    - name: service httpd server      
      service: name=httpd state=started enabled=yes
```

![ansible超详细讲解，值得收藏](https://p3-tt.byteimg.com/origin/pgc-image/47e70527ae6542d2bf253af887777a5d?from=pc)



下面看一个例子：安装memcache

```
# memcache.yml
- hosts: web  

  tasks:    
    - name: install memcached server      
      yum: name=memcached state=present          
        
    - name: configure memcached server      
      template: src=./memcached.j2 dest=/etc/sysconfig/memcached          
        
    - name: service memcached server      
      service: name=memcached state=started enabled=yes          
        
    - name: check memcached server      
      shell: ps aux|grep memcached      
      register: check_mem          
        
    - name: debug memcached variables      
      debug:        
        msg: "{{check_mem.stdout_lines}}"
# memcached.j2，通过facts获取的目标主机内存总量
PORT="11211"
USER="memcached"
MAXCONN="1024"
CACHESIZE="{{ansible_memtotal_mb // 2}}"
OPTIONS=""
```

这里我们用到了一个新的模块：template，这个相当于Django的模板语法，支持Jinjia2渲染引擎和语法。以上实现了playbook的大部分操作，但是那只是常规操作，还有一些更加灵活的问题需要处理，例如：

**我们只想要执行一个playbook中的某个任务？**

**检测nginx状态，如果正常就启动或重启，不正常就忽略，执行其他任务**

**如果nginx的配置文件没有变化，我们就不执行启动或重启命令**

以上这些情况都需要进行逻辑判断，ansible强大的地方也正是这里，下面我们看一下task的任务控制流程

# **Task任务控制**

任务控制包括以下逻辑关键字：

1. 条件判断 when
2. 循环语句 with_items
3. 触发器 handlers
4. 标签 tags
5. 包含 include
6. 忽略错误 ignore_error
7. 错误处理 change

# **条件判断**

假设我们安装Apache，在centos上安装的是httpd，在Ubuntu上安装的是httpd2，因此我们需要判断主机信息，安装不同的软件。

```
- hosts: web  
  tasks:    
    - name: Install CentOS Httpd      
      yum: name=httpd state=present      
      when: ( ansible_distribution == "CentOS" )          
        
    - name: Install Ubuntu Httpd      
      yum: name=httpd2 state=present      
      when: ( ansible_distribution == "Ubuntu" )
```

给task加上when条件，在执行的时候，就会先判断条件是否满足，如果满足则执行任务，不满足就不执行此任务。我们再看一个例子：如果Apache服务不正常就重启，否则跳过。

```
- hosts: web  
  tasks:    
    - name: check httpd server      
      command: systemctl is-active httpd      
      register: check_httpd          
        
    - name: httpd restart      
      service: name=httpd state=restarted      
      when: check_httpd.rc == 0
```

# **循环命令 with_items**

启动多个服务，例如nginx、httpd

```
- hosts: web  
  tasks:    
    - name: Service Start      
      service: name={{item}} state=restarted      
      with_items:        
        - nginx        
        - httpd
```

拷贝多个配置文件

```
- hosts: web  
  tasks:    
    - name: Copy Configure File      
      copy:         
        src: {{item.src}}        
        dest: {{item.dest}}        
        mode: {{item.mode}}      
      with_items:        
        - { src: './nginx.conf', dest: '/etc/nginx/conf/nginx.conf' }        
        - { src: './httpd.conf', dest: '/etc/httpd/conf/httpd.conf' }
```

# **触发器 handlers**

当某个任务发生变化时，触发另一个任务的执行，例如如果httpd的配置文件发生了变化，就执行重启任务

```
- hosts: web  
  tasks:    
    - name: install httpd server      
      yum: name=httpd state=present          
        
    - name: configure httpd server      
      copy: src=httpd.conf dest=/etc/httpd/conf/httpd.conf      
      notify: # 条用名称为Restart Httpd Server的handlers，可以写多个        
        - Restart Httpd Server            
          
    - name: service httpd server      
      service: name=httpd state=started enabled=yes        
  
  handlers:    
    - name: Restart Httpd Server      
      service: name=httpd state=restarted
```

handlers执行的时候需要注意，虽然是在某个任务被触发的，但是它必须等到所有的task执行完成后，才会执行handlers里面被触发过的命令，如果在执行前，有另一个task执行失败了，那么被触发的handlers也不会执行。

# **tags标签**

对任务指定标签后，我们在使用ansible-playbook执行的时候就可以指定标签来执行任务，不需要执行所有的任务，标签的设置有三种情况：1. 一个任务设置一个标签 2.一个任务设置多个标签 3. 多个任务设置一个标签

```
- hosts: web  
  tasks:    
    - name: install httpd server      
      yum: name=httpd state=present      
      tags: install          
        
    - name: configure httpd server      
      copy: src=httpd.conf dest=/etc/httpd/conf/httpd.conf      
      notify: # 条用名称为Restart Httpd Server的handlers，可以写多个        
        - Restart Httpd Server      
      tags: configure          
        
    - name: service httpd server      
      service: name=httpd state=started enabled=yes      
      tags: start        
      
  handlers:    
    - name: Restart Httpd Server      
      service: name=httpd state=restarted
```

执行指定tags的命令：**ansible-playbook httpd.yml -t "configure"**

跳过指定tags的命令：**ansible-playbook httpd.yml --skip-tags "install"**

# **include包含**

我们可以把任务单独写在一个yaml文件中，然后在其他需要用到的任务中通过include_tasks: xxx.yml引入，举例如下：

```
# a.yml
- name: restart httpd service  
  service: name=httpd state=restarted
# b.yml
- hosts: web  
  tasks:    
    - name: configure httpd server      
      copy: src=httpd.conf dest=/etc/httpd/conf/httpd.conf          
        
    - name: restat httpd      
      include_tasks: ./a.yml
```

当然我们也可以把两个完整的playbook合并起来

```
# a.yml
- hosts: web  
  tasks:    
    - name: install httpd server      
      yum: name=httpd state=present
# b.yml
- hosts: web  
  tasks:    
    - name: configure httpd server      
      copy: src=httpd.conf dest=/etc/httpd/conf/httpd.conf
# total.yml
- import_playbook: ./a.yml
- import_playbook: ./b.yml
```

在执行total.yml的时候，实际上就是先执行a.yml，然后再执行b.yml，里面的内容实际并不是真正的合并

# **忽略错误ignore_errors**

我们知道，在执行playbook的时候，如果其中某个任务失败了，它下面的任务就不会再执行了，但是有时候我们并不需要所有任务都成功，某些任务是可以失败的，那么这个时候就需要进行容错，就是在这个任务失败的时候，不影响它后面的任务执行。

```
- hosts: web  
  tasks:    
    - name: check httpd status      
      command: ps aux|grep httpd      
      register: httpd_status      
      ignore_errors: yes # 如果查询语句执行失败，继续向下执行重启任务          
        
    - name: restart httpd      
      service: name=httpd state=restarted
```

# **错误处理**

- force_handlers: yes 强制调用handlers只要handlers被触发过，无论是否有任务失败，均调用handlers

```
- hosts: web 
  force_handlers: yes   
  
  tasks:   
    - name: install httpd     
      yum: name=httpd state=present         
        
    - name: install fuck     
      yum: name=fuck state=present   
  
  handlers:   
    - name: restart httpd     
      service: name=httpd state=restarted
```

- change_when

当任务执行的时候，如果被控主机端发生了变化，change就会变化，但是某些命令，比如一些shell命令，只是查询信息，并没有做什么修改，但是一直会显示change状态，这个时候我们就可以强制把change状态关掉。

```
- hosts: web 
  tasks:   
    - name: test task     
    shell: ps aux     
    change_when: false
```

再看一个例子，假如我们修改配置文件成功了，就执行重启命令，否则不执行重启

```
- hosts: web 
  tasks:   
    - name: install nginx server     
      yum: name=nginx state=present         
        
    - name: configure nginx     
      copy: src=./nginx.conf dest=/etc/nginx/conf/nginx.conf        

    # 执行nginx检查配置文件命令   
    - name: check nginx configure     
      command: /usr/sbin/nginx -t     
      register: check_nginx     
      changed_when: ( check_nginx.stdout.find('successful') )         
        
    - name: service nginx server     
      service: name=nginx state=restarted
```

# Jinja模板

jinja模板是类似Django的模板，如果做过Django的同学应该是比较熟悉的，我们使用jinja来配置一下nginx的负载均衡。

```
- hosts: web 
  vars:   
    - http_port: 80   
    - server_name: web.com     

  tasks:   
    - name: instal nginx server     
      yum: name=nginx state=present         
        
    - name: configure nginx     
      template: src=./nginx.conf dest=/etc/nginx/conf/nginx.conf         
        
    - name: start nginx     
      service: name=nginx state=started enabled=yes
```

要使Jinja语法生效，必须使用template模块处理，这个模块和copy类似，但是它支持Jinja语法渲染

```
# nginx.conf
 upstream {{server_name}} { 
   {% for i in range(2) %}  
     server 192.168.143.12{{i}}:{{http_port}};  
     server 192.168.143.12{{i}}:{{http_port}};
   {% endfor %}
 }
 server {  
   listen {{http_port}};  
   server_name {{server_name}}  
   location / {    
     proxy_pass http://web.com;    
     include proxy_params; 
   }
 }
```

在配置文件中就可以使用playbook中定义的变量，我们在配置MySQL主从复制集群的时候，对于my.cnf文件，master主机和slave主机的配置是不同的，这样就可以根据主机名，使用Jinja中的if语法进行条件渲染

```
[mysqld]
{% if ansible_fqdn == "mysql_master" %} 
	log-bin=mysql-bin 
  server-id=1
{% else %} 
  server-id=2
{% endif %}
```

这样就完成了配置区分，执行同样的template拷贝命令，在不同的机器上是不同的配置文件。**PS：**

**ansible_fqdn**: 这个是gather_facts任务获取的变量，我们也可以使用其他变量进行判断**mysql_master**: 这个是需要配置主从复制的master主机hostname，需要提前设置，也是可以用ansible设置的

# Ansible Roles

最后我们要讲一下ansible中最重要的一个概念-roles，如果前面的你都搞清楚了，那么roles是非常简单的。总的来说roles就是把我们前面讲过的东西进行了一个排版，它规定了严格的目录格式，我们必须按照目录结构和文件名进行创建，否则它的文件系统就加载不到。目录格式如下：

![ansible超详细讲解，值得收藏](https://p3-tt.byteimg.com/origin/pgc-image/c597b1b340644993a1cff74d0a16001b?from=pc)



- mysql.yml：playbook文件
- mysql：roles目录，也是角色名
- files：存放文件、压缩包、安装包等
- handlers：触发任务放在这里
- tasks：具体任务
- templates：存放通过template渲染的模板文件
- vars：定义变量
- meta：任务依赖关系

那些main.yml也是必须的，名字必须是这样，目录名称也必须相同，但是不是每个目录都是必须的，下面我们把httpd的那个例子用roles写一下：

```
- hosts: web  
  tasks:    
    - name: install httpd server      
      yum: name=httpd state=present      
      tags: install          
        
    - name: configure httpd server      
      template: src=httpd.conf dest=/etc/httpd/conf/httpd.conf      
      notify: # 条用名称为Restart Httpd Server的handlers，可以写多个        
        - Restart Httpd Server      
      tags: configure          
        
    - name: service httpd server      
      service: name=httpd state=started enabled=yes      
      tags: start        
      
  handlers:    
    - name: Restart Httpd Server      
    service: name=httpd state=restarted
```

就把上面这一段改成roles的格式，目录结构如下：

![ansible超详细讲解，值得收藏](https://p3-tt.byteimg.com/origin/pgc-image/eb910b70a3634b2c98229b0dbc7cefb8?from=pc)



```
# httpd/handlers/main.yml
- name: Restart Httpd Server  
  service: name=httpd state=restarted
# httpd/tasks/config.xml
- name: configure httpd server  
  template: src=httpd.conf dest=/etc/httpd/conf/httpd.conf  
  notify: # 条用名称为Restart Httpd Server的handlers，可以写多个    
    - Restart Httpd Server  
  tags: configure
# httpd/tasks/install.yml
- name: install httpd server 
  yum: name=httpd state=present  
  tags: install
# httpd/tasks/start.yml
- name: service httpd server  
  service: name=httpd state=started enabled=yes  
  tags: start
# httpd/tasks/main.yml
- include_tasks: install.yml
- include_tasks: config.yml
- include_tasks: start.yml
# httpd1.yml
- hosts: web  
  roles:    
    - role: nginx    
    # - nginx 与上面是等价的，但是上面的可以增加tags
```

最后再与httpd1.yml同级目录下执行**ansible-playbook httpd1.yml**即可（我这里实际是httpd2.yml，不要在意这些细节）

![ansible超详细讲解，值得收藏](https://p6-tt.byteimg.com/origin/pgc-image/abb1d04ab856415a9de210522daf2ee4?from=pc)



# Galaxy

最后我们再介绍一个官方网站：https://galaxy.ansible.com

Galaxy有别人写好的roles，比如你想要安装Nginx，那么在上面搜索nginx，然后会提供一个下载命令：**ansible-galaxy install geerlingguy.nginx**，执行以后，会把它下载到/root/.ansible/roles这个目录下。

到这里，ansible的讲解我们就写完了，ansible是用python开发的，所以我们经常会把它和python结合起来使用，后面我们会把python操作ansible写一下。