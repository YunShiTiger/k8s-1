## 运维自动化-Ansible

#### Ansible 是什么

Ansible 简单的说是一个配置管理系统(configuration management system)。你只需要可以使用 ssh 访问你的服务器或设备就行。它也不同于其他工具，因为它使用推送的方式，而不是像 puppet 等 那样使用拉取安装agent的方式。你可以将代码部署到任意数量的服务器上!

####  Ansible能做什么

ansible可以帮助我们完成一些批量任务，或者完成一些需要经常重复的工作。
比如：同时在100台服务器上安装nginx服务，并在安装后启动它们。
比如：将某个文件一次性拷贝到100台服务器上。
比如：每当有新服务器加入工作环境时，你都要为新服务器部署某个服务，也就是说你需要经常重复的完成相同的工作。
这些场景中我们都可以使用到ansible。

#### Ansible特性

模块化：调用特定的模块，完成特定任务
有Paramiko，PyYAML，Jinja2（模板语言）三个关键模块
支持自定义模块
基于Python语言实现
部署简单，基于python和SSH(默认已安装)，agentless
安全，基于OpenSSH
支持playbook编排任务
幂等性：一个任务执行1遍和执行n遍效果一样，不因重复执行带来意外情况
无需代理不依赖PKI（无需ssl）
可使用任何编程语言写模块
YAML格式，编排任务，支持丰富的数据结构
较强大的多层解决方案
Ansible架构

![img](C:\Users\wzxmt\AppData\Local\Temp\ksohtml18352\wps3.jpg) 

#### Ansible工作原理

![img](C:\Users\wzxmt\AppData\Local\Temp\ksohtml18352\wps4.jpg) 

#### Ansible主要组成部分功能说明

PLAYBOOKS：
​      任务剧本（任务集），编排定义Ansible任务集的配置文件，由Ansible顺序依次执行，通常是JSON格式的YML文件
INVENTORY：
​      Ansible管理主机的清单/etc/anaible/hosts
MODULES：
​      Ansible执行命令的功能模块，多数为内置的核心模块，也可自定义,ansible-doc –l 可查看模块
PLUGINS：

​      模块功能的补充，如连接类型插件、循环插件、变量插件、过滤插件等，该功能不常用
API：
​      供第三方程序调用的应用程序编程接口
ANSIBLE：
​      组合INVENTORY、 API、 MODULES、PLUGINS的绿框，可以理解为是ansible命令工具，其为核心执行工具

### Ansible 功能详解

#### 配置文件

| 配置文件或指令            | 描述                                   |
| ------------------------- | -------------------------------------- |
| /etc/ansible/ansible.cfg  | 主配置文件，配置ansible工作特性        |
| /etc/ansible/hosts        | 主机清单                               |
| /etc/ansible/roles/       | 存放角色的目录                         |
| /usr/bin/ansible          | 主程序，临时命令执行工具               |
| /usr/bin/ansible-doc      | 查看配置文档，模块功能查看工具         |
| /usr/bin/ansible-galaxy   | 下载/上传优秀代码或Roles模块的官网平台 |
| /usr/bin/ansible-playbook | 定制自动化任务，编排剧本工具           |
| /usr/bin/ansible-pull     | 远程执行命令的工具                     |
| /usr/bin/ansible-vault    | 文件加密工具                           |
| /usr/bin/ansible-console  | 基于Console界面与用户交互的执行工具    |

####  Inventory 主机清单

[webservers]     >  定义了一个组名   
alpha.example.org   >  组内的单台主机
192.168.100.10 [dbservers] 192.168.100.10 >  一台主机可以是不同的组，这台主机同时属于[webservers] 
Inventory 参数说明
ansible_ssh_host
   将要连接的远程主机名.与你想要设定的主机的别名不同的话,可通过此变量设置. 
ansible_ssh_port
   ssh端口号.如果不是默认的端口号,通过此变量设置.这种可以使用 ip:端口 192.168.1.100:2222
ansible_ssh_user
   默认的 ssh 用户名
ansible_ssh_pass
   ssh 密码(这种方式并不安全,我们强烈建议使用 --ask-pass 或 SSH 密钥)
ansible_sudo_pass
   sudo 密码(这种方式并不安全,我们强烈建议使用 --ask-sudo-pass)
ansible_sudo_exe (new in version 1.8)
   sudo 命令路径(适用于1.8及以上版本)
ansible_connection
   与主机的连接类型.比如:local, ssh 或者 paramiko. Ansible 1.2 以前默认使用 paramiko.1.2 以后默认使用 'smart','smart' 方式会根据是否支持 ControlPersist, 来判断'ssh' 方式是否可行.
ansible_ssh_private_key_file
   ssh 使用的私钥文件.适用于有多个密钥,而你不想使用 SSH 代理的情况.
ansible_shell_type
   目标系统的shell类型.默认情况下,命令的执行使用 'sh' 语法,可设置为 'csh' 或 'fish'.
ansible_python_interpreter
   目标主机的 python 路径.适用于的情况: 系统中有多个 Python, 或者命令路径不是"/usr/bin/python",比如  \*BSD, 或者 /usr/bin/python 不是 2.X 版本的 Python.
   我们不使用 "/usr/bin/env" 机制,因为这要求远程用户的路径设置正确,且要求 "python" 可执行程序名不可为 python以外的名字(实际有可能名为python26).
   与 ansible_python_interpreter 的工作方式相同,可设定如 ruby 或 perl 的路径....

上面的参数用这几个例子来展示可能会更加直观

some_host     ansible_ssh_port=2222   ansible_ssh_user=manager
aws_host      ansible_ssh_private_key_file=/home/example/.ssh/aws.pem
freebsd_host    ansible_python_interpreter=/usr/local/bin/python
ruby_module_host  ansible_ruby_interpreter=/usr/bin/ruby.1.9.3

#### Ansible常用命令语法

ansible <host-pattern> [-m module_name] [options]

指令 匹配规则的主机清单 -m 模块名 选项

--version 显示版本

-a 模块参数（如果有）

-m module 指定模块，默认为command

-v 详细过程 –v-vvv更详细

--list-hosts 显示主机列表，可简写--list

-k, --ask-pass 提示连接密码，默认Key验证

-K，--ask-become-pass 提示使用sudo密码

-C, --check 检查，并不执行

-T, --timeout=TIMEOUT 执行命令的超时时间，默认10s

-u, --user=REMOTE_USER 执行远程执行的用户

-U， SUDO_USER, --sudo-user 指定sudu用户

-b, --become 代替旧版的sudo 切换

#### ansible-doc: 显示模块帮助

ansible-doc [options] [module...]

-a 显示所有模块的文档

-l, --list 列出可用模块

-s, --snippet 显示指定模块的简要说明

#### ansible 常用命令模块

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

ansiable特殊用法

```bash
组嵌套
[db]
172.16.1.51
[test]
10.0.0.7
[web_test:tmp]
db
test

[root@m01 ~]# vim 1.yaml
---
- hosts: 10.0.0.7
  remote_user: root
  vars:  #变量
    touch_file: imoocc.file
  tasks:
    - name: touch file
      file : state=touch dest="/tmp/{{touch_file}}"
定义playbook的变量
1. playbook的yaml 文件中定义变量赋值

2.--extra-vars执行参数复制给变量
ansible-playbook 1.yaml --extra-vars "touch_file=jensor"

3.在文件中定义变量
vim /etc/ansible/hosts
10.0.0.7
[test:vars]
touch_file=jensor3
ansible-playbook 1.yaml

4.注册变量
register 关键字可以存储指定命令的输出结果到一个自定义的变量中
- name：get time
  shell: date
  register: date_output

---
- hosts : 10.0.0.7
  remote_user : root
  vars :  #变量
    touch_file : imoocc.file
  tasks :
    - name: get time
      shell: date
      register: date_output
    - name: touch file
      copy: content={{date_output}} dest="/tmp/{{touch_file}}"

playbook基本语句
1.条件语句
when
- hosts: 10.0.0.7
  remote_user: root
  tasks:
  - name: "touch flag file"
    file: state=touch dest="/tmp/this_is_{{ansible_distribution}}"
    when: (ansible_distribution == "CentOS" and ansible_distribution_major_version == "6") or
          (ansible_distribution == "Debian" and ansible_distribution_major_version == "7")
2.标准循环
---
- hosts: test
  remote_user: root
  tasks:
    - name: add server users
      user: name={{item.name}} state=present groups={{item.groups}}
      with_items:
          - { name: 'testuser1',groups: 'whell'}
          - { name: 'testuser2',groups: 'root'}

3.遍历字典
---
- hosts: test
  remote_user: root
  tasks:
    - name: add server users
      user: name={{item.key}} state=present groups={{item.value}}
      with_dict:
          - { 'testuser3' : 'wheel', 'testuser4' : 'root' }

遍历目录
---
- hosts: 10.0.0.7
  remote_user: root
  tasks:
    - file: dest=/tmp/x state=directory
    - copy: src={{ item }} dest=/tmp/x owner=root mode=600
      with_fileglob:
           - aa/*

2.条件循环语句
---
- hosts: 10.0.0.7
  remote_user: root
  tasks:
    - debug: msg="{{ item.key }} is the winner"
      with_dict: {'jeson':{'english':60,'chinese':30},'tom':{'english':20,'chinese':30}}
      when: item.value.english >=60

4.
（1）默认会检查命令和模块的返回状态，遇到错误就中断playbook的执行
加入一个参数：ignore_error:yes
---
- hosts: test
  remote_user: root
# remote_user: www
# sudo yes
  tasks:
    - name: igonre file
      shell: /bin/false
      ignore_errors: yes
    - name: touch file
      file:  path=/tmp/test.txt state=touch owner=root group=root mode=0700
自定义错误
---
- hosts: test
  remote_user: root
  tasks:
    - name: get process
      shell: ps -ef|wc -l
      register: process_count
      failed_when: process_count >3
    - name: touch file
      file:  path=/tmp/test2.txt state=touch owner=jeson group=jeson mode=0700

自定义change状态
---
- hosts: test
  remote_user: root
  tasks:
    - name: get prosecc
      shell: touch /tmp/chang_test.txt
      changed_when: false #关闭change状态

打标签：
---
- hosts: test
  remote_user: root
  tasks:
    - name: create file1
      file: path=/tmp/file1.txt state=touch
      tags:
          - cfile1
          - cfile3
    - name: create file2
      file: path=/tmp/file2.txt state=touch
      tags:
          - cfile2
（2）标签的使用
-t ：执行指定的任务的tag标签任务
--skip-tags: 执行--skip-tags标签之外的标签任务
ansible-playbook 10.yaml -t cfile1

include的用法
include_tasks/include:动态的包含tasks任务列表执行

vim touch1.yaml
---
- name: create file1
  file: path=/tmp/file1.txt state=touch
  tags:
    - cfile1
    - cfile3
vim touch2.yaml
---
- name: create file2
  file: path=/tmp/file2.txt state=touch
  tags:
    - cfile2

[root@m01 play-book]# vim 11.yaml
---
- hosts: test
  remote_user: root
  tasks:
    - include_tasks: touch1.yaml
    - include_tasks: touch2.yaml



ansible官方网站的建议playbook剧本结构如下：

production        # 正式环境的inventory文件
staging           #测试环境用得inventory文件
group_vars/  # 机器组的变量文件
      group1        
      group2
host_vars/   #执行机器成员的变量
      hostname1     
      hostname2
================================================
site.yml                 # 主要的playbook剧本
webservers.yml    # webserver类型服务所用的剧本
dbservers.yml       # 数据库类型的服务所用的剧本

roles/ #角色
      webservers/        #webservers这个角色相关任务和自定义变量
           tasks/
               main.yml
           handlers/
               main.yml
           vars/            #
                main.yml
        dbservers/         #dbservers这个角色相关任务和定义变量
            ...
      common/         # 公共的
           tasks/        #   
                main.yml    # 
           handlers/     #处理器,由某件事触发执行的操作
                main.yml    # handlers file.
           vars/         # 角色所用到的变量
                main.yml    # 
===============================================
      templates/    #
            ntp.conf.j2 # 模版文件
      files/        #   用于上传存放文件的目录
            bar.txt     #  
            foo.sh      # 
      meta/         # 角色的依赖
            main.yml    # 

```

