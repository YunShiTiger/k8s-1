# rabbitmq安装

## 一、RabbitMQ简单介绍

RabbitMQ就是当前最主流的消息中间件之一。RabbitMQ是一个开源的AMQP实现，服务器端用Erlang语言编写，支持多种客户端，如：Python、Ruby、.NET、Java、JMS、C、PHP、ActionScript、XMPP、STOMP等，支持AJAX。用于在分布式系统中存储转发消息，在易用性、扩展性、高可用性等方面表现不俗。
在目前分布式的大环境下，成为非常常用的消息队列，以下详细说明在linux环境下，怎么通过源码安装rabbitmq，并列举简单的维护，方便运维同学能更好的维护rabbitmq的正常运行。由于一般生产环境，不管是erlang还是 rabbitmq都不能随便进行版本升级，每次升级都是要谨慎的，所以这里推荐都使用源码安装，这样就固定了版本，不会出现通过yum安装的话，不小心升级了版本导致服务故障等的问题。当然yum安装会更简单，这里就不做介绍，有兴趣的参考官方文档即可。

## 二、安装rabbitmq

RabbitMQ是Erlang语言编写，安装RabbitMQ之前，需要先安装Erlang，Elang环境一定要与RabbitMQ版本匹配，可根据官网查看RabbitMQ版本对应[Erlang](https://www.rabbitmq.com/which-erlang.html#erlang-repositories)的版本；我们安装rabbitmq3.7.20版本，对应的erlang是最低是21.3，我们选择21.3

#### 1、安装Erlang

进入[Erlang](https://www.erlang.org/downloads)官网，下载对应版本Erlang，并解压

```
wget http://erlang.org/download/otp_src_21.3.tar.gz
tar xf otp_src_21.3.tar.gz
cd otp_src_21.3
```

安装依赖

```
yum install -y make gcc gcc-c++ m4 openssl openssl-devel ncurses-devel unixODBC unixODBC-devel java java-devel
```

初始化配置

```
./configure --prefix=/usr/local/erlang
```

出现wx相关提示，可以忽略不记，不影响正常编译

编译安装

```
make && make install
```

加入环境变量

```
echo 'export PATH=/usr/local/erlang/bin:$PATH' >>/etc/profile
source /etc/profile
```

到此，既安装完成，直接输入erl，得到如下

```
[root@test ~]# erl
Erlang/OTP 21 [erts-10.3] [source] [64-bit] [smp:1:1] [ds:1:1:10] [async-threads:1] [hipe]
Eshell V10.3  (abort with ^G)
1>
```

#### 2、安装rabbitmq-server

在[官网](https://www.rabbitmq.com/install-generic-unix.html)上,或者在[github](https://github.com/rabbitmq/rabbitmq-server/releases)上，找到对应版本下载

```
wget https://github.com/rabbitmq/rabbitmq-server/releases/download/v3.7.20/rabbitmq-server-generic-unix-3.7.20.tar.xz
```

解压

```
tar xf rabbitmq-server-generic-unix-3.7.20.tar.xz -C /usr/local/src
```

创建软连接，添加环境变量

```
ln -s /usr/local/src/rabbitmq_server-3.7.20 /usr/local/rabbitmq
echo 'export PATH=/usr/local/rabbitmq/sbin:$PATH' >>/etc/profile
source /etc/profile
```

到此，服务已经部署完毕！

## 三、rabbitmq简单运用

默认rabbitmq是没有配置文件的，也是可以启动服务的。若是需要配置文件，去[github](https://github.com/rabbitmq/rabbitmq-server/tree/master/docs)上，复制一个配置文件模版过来，最新的3.7.0以上的版本可以使用新的key-value形式的配置文件rabbitmq.conf，和原来erlang格式的advanced.config相结合，解决一下key-value形式不好定义的配置。yum或者rpm安装的rabbitmq的配置文件在/etc/rabbitmq下，而编译安装默认的配置文件路径在--prefix指定目录下的etc/rabbitmq目录下。

#### 1、启动服务与停止服务

启动服务

```
rabbitmq-server （前台运行）
rabbitmq-server -detached(后台运行)
```

查看端口

```
[root@test ~]# netstat -lntup|egrep "5672|25672|15672"
tcp        0     0 0.0.0.0:25672      0.0.0.0:*               LISTEN      50904/beam.smp
tcp6      0     0 :::5672                 :::*                LISTEN      50904/beam.smp
```

停服务

```
rabbitmqctl stop
```

#### 2、开启Web管理界面

加载插件管理界面

```
rabbitmq-plugins enable rabbitmq_management      
```

查看端口

```
[root@test ~]# netstat -lntup|egrep "5672|25672|15672"
tcp        0     0 0.0.0.0:15672      0.0.0.0:*               LISTEN      50904/beam.smp
tcp        0     0 0.0.0.0:25672      0.0.0.0:*               LISTEN      50904/beam.smp
tcp6      0     0 :::5672                 :::*                LISTEN      50904/beam.smp
```

浏览器访问 [http://ip:15672](http://ip:15672),进入如下页面就证明插件启动成功了。

#### 3、添加用户

使用默认的用户 guest / guest （此也为管理员用户）登陆，会发现无法登陆，报错：User can only log in via localhost。那是因为默认是限制了guest用户只能在本机登陆，也就是只能登陆localhost:15672。可以通过修改配置文件rabbitmq.conf，取消这个限制；一般为了安全考虑，会删除此用户，添加新用户。

```
添加用户： 
rabbitmqctl add_user username password
删除用户： 
rabbitmqctl delete_user username
修改密码： 
rabbitmqctl change_password username newpassword
设置用户角色： 
rabbitmqctl set_user_tags username administrator
列出用户： 
rabbitmqctl list_users
```

#### 4、用户角色

- 超级管理员(administrator)
  可登陆管理控制台，可查看所有的信息，并且可以对用户，策略(policy)进行操作。
- 监控者(monitoring)
  可登陆管理控制台，同时可以查看rabbitmq节点的相关信息(进程数，内存使用情况，磁盘使用情况等)
- 策略制定者(policymaker)
  可登陆管理控制台, 同时可以对policy进行管理。但无法查看节点的相关信息(上图红框标识的部分)。
- 普通管理者(management)
  仅可登陆管理控制台，无法看到节点信息，也无法对策略进行管理。
- 其他
  无法登陆管理控制台，通常就是普通的生产者和消费者。

#### 5、创建Virtual Hosts

![这里写图片描述](http://m.qpic.cn/psc?/V149W3Xb05f9IQ/NA7c.P04lftfqRw.HyJC1YdlBFUuGBBzxe7u58WRikUqq.b6zKdX.eWhMQ7ffJVxaCceszo1oolDE1xAtghKxS4bhdq7VfhXkjBPzbga67w!/b&bo=bQeFAgAAAAADB88!&rf=viewer_4)

选中Admin用户，设置权限：
![这里写图片描述](http://m.qpic.cn/psc?/V149W3Xb05f9IQ/NA7c.P04lftfqRw.HyJC1Su1MvvxNLZ.NEP1Q8IXddhm6J2P0dhywhPjMcZAAVGBRZ2ncRGHxMKU7t1bDNr.3cJoX1Yopn9mRL8LW1NYCSM!/b&bo=Tgc3AwAAAAADF08!&rf=viewer_4)
看到权限已加：
![这里写图片描述](http://m.qpic.cn/psc?/V149W3Xb05f9IQ/NA7c.P04lftfqRw.HyJC1UZEq*DfHNG56J9uYSJQtWszLCLck1gBG1sXkMcD6dPvB9qaf5AjtEvFCTQGkrr1c*CEQwOgTLp6Y6ueIZwCNV4!/b&bo=QAU7AgAAAAADF04!&rf=viewer_4)

#### 6、权限管理

```
列出所有用户权限： 
rabbitmqctl list_permissions
查看制定用户权限： 
rabbitmqctl list_user_permissions username
清除用户权限： 
rabbitmqctl clear_permissions [-p vhostpath] username
设置用户权限： 
rabbitmqctl set_permissions [-p vhostpath] username conf write read
```

注意：

​		conf: 一个正则匹配哪些资源能被该用户访问
​		write：一个正则匹配哪些资源能被该用户写入
​		read：一个正则匹配哪些资源能被该用户读取

#### 7、修改数据文件和日志文件的存放位置

默认数据文件与日志文件在默认安装路劲的var目录下，要更改文件存放位置。需要以下操作：

(1)先创建数据文件和日志文件存放位置的目录并给权限

```
mkdir -p /data/rabbitmq/{data,log}
```

(2)新增环境参数配置文件

```
cat << EOF >/usr/local/rabbitmq/etc/rabbitmq/rabbitmq-env.conf
RABBITMQ_MNESIA_BASE=/data/rabbitmq/data
RABBITMQ_LOG_BASE=/data/rabbitmq/log
EOF
```

(3)重启服务

​		注：更换完位置后原有队列中的数据就没有了，而且原有的rabbitmq用户也需要重建。

## 四、RabbitMQ的五种队列模式：

##### 1.1 simple简单模式

![在这里插入图片描述](http://images.cnblogs.com/cnblogs_com/wzxmt/1506688/o_200301065013mq01.png)

1. 消息产生着§将消息放入队列
2. 消息的消费者(consumer) 监听(while) 消息队列,如果队列中有消息,就消费掉,消息被拿走后,自动从队列中删除(隐患 消息可能没有被消费者正确处理,已经从队列中消失了,造成消息的丢失)应用场景:聊天(中间有一个过度的服务器;p端,c端)

##### 1.2 work工作模式(资源的竞争)

![在这里插入图片描述](http://images.cnblogs.com/cnblogs_com/wzxmt/1506688/o_200301065026mq02.png)

1. 消息产生者将消息放入队列消费者可以有多个,消费者1,消费者2,同时监听同一个队列,消息被消费?C1 C2共同争抢当前的消息队列内容,谁先拿到谁负责消费消息(隐患,高并发情况下,默认会产生某一个消息被多个消费者共同使用,可以设置一个开关(syncronize,与同步锁的性能不一样) 保证一条消息只能被一个消费者使用)
2. 应用场景:红包;大项目中的资源调度(任务分配系统不需知道哪一个任务执行系统在空闲,直接将任务扔到消息队列中,空闲的系统自动争抢)

##### 1.3 publish/subscribe发布订阅(共享资源)

![在这里插入图片描述](http://images.cnblogs.com/cnblogs_com/wzxmt/1506688/o_200301065037mq03.png)

1. X代表交换机rabbitMQ内部组件,erlang 消息产生者是代码完成,代码的执行效率不高,消息产生者将消息放入交换机,交换机发布订阅把消息发送到所有消息队列中,对应消息队列的消费者拿到消息进行消费
2. 相关场景:邮件群发,群聊天,广播(广告)

##### 1.4 routing路由模式

![在这里插入图片描述](http://images.cnblogs.com/cnblogs_com/wzxmt/1506688/o_200301065048mq04.png)

1. 消息生产者将消息发送给交换机按照路由判断,路由是字符串(info) 当前产生的消息携带路由字符(对象的方法),交换机根据路由的key,只能匹配上路由key对应的消息队列,对应的消费者才能消费消息;
2. 根据业务功能定义路由字符串
3. 从系统的代码逻辑中获取对应的功能字符串,将消息任务扔到对应的队列中业务场景:error 通知;EXCEPTION;错误通知的功能;传统意义的错误通知;客户通知;利用key路由,可以将程序中的错误封装成消息传入到消息队列中,开发者可以自定义消费者,实时接收错误;

##### 1.5 topic 主题模式(路由模式的一种)

![在这里插入图片描述](http://images.cnblogs.com/cnblogs_com/wzxmt/1506688/o_200301065100mq05.png)

1. 星号井号代表通配符
2. 星号代表多个单词,井号代表一个单词
3. 路由功能添加模糊匹配
4. 消息产生者产生消息,把消息交给交换机
5. 交换机根据key的规则模糊匹配到对应的队列,由队列的监听消费者接收消息消费



