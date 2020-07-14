## tomcat 调优

可以考虑从内存,并发,缓存,安全,网络,系统等进行入手

### 内存优化

#### 1、修改内存等 JVM相关配置

```bash
Linux下修改TOMCAT_HOME/bin/catalina.sh
JAVA_OPTS="-server -XX:PermSize=512M -XX:MaxPermSize=1024m -Xms2048m -Xmx2048m
windows下修改TOMCAT_HOME/bin/catalina.bat
set JAVA_OPTS=-server -XX:PermSize=512M -XX:MaxPermSize=1024m -Xms2048m -Xmx2048m
```

调整堆大小的的目的是最小化垃圾收集的时间，以在特定的时间内最大化处理客户的请求

#### 2、参数介绍

- -server：启用 JDK的 server 版本；
- -Xms：Java虚拟机初始化时堆的最小内存，一般与 Xmx配置为相同值，这样的好处是GC不必再为扩展内存空间而消耗性能；
- -Xmx：Java虚拟机可使用堆的最大内存；
- -XX:PermSize：Java虚拟机永久代大小；
- -XX:MaxPermSize：Java虚拟机永久代大小最大值；

#### 3、验证

可以利用JDK自带的工具进行验证，这些工具都在JAVA_HOME/bin目录下：
1）jps：用来显示本地的java进程，以及进程号，进程启动的路径等。
2）jmap：观察运行中的JVM 物理内存的占用情况，包括Heap size , Perm size等。
进入命令行模式后，进入JAVA_HOME/bin目录下，然后输入jps命令：

### 并发优化

Connector是连接器，负责接收客户的请求，以及向客户端回送响应的消息。所以 Connector的优化是重要部分。默认情况下 Tomcat只支持200线程访问，超过这个数量的连接将被等待甚至超时放弃，所以我们需要提高这方面的处理能力。

![在这里插入图片描述](https://img-blog.csdnimg.cn/20181120143608487.png)

参数说明

- maxThreads 客户请求最大线程数
- minSpareThreads Tomcat初始化时创建的 socket 线程数
- maxSpareThreads Tomcat连接器的最大空闲 socket 线程数
- enableLookups 若设为true, 则支持域名解析，可把 ip 地址解析为主机名
- redirectPort 在需要基于安全通道的场合，把客户请求转发到基于SSL 的 redirectPort 端口
- acceptAccount 监听端口队列最大数，满了之后客户请求会被拒绝（不能小于maxSpareThreads ）
- connectionTimeout 连接超时
- minProcessors 服务器创建时的最小处理线程数
- maxProcessors 服务器同时最大处理线程数
- URIEncoding URL统一编码

### 缓存优化

![在这里插入图片描述](https://img-blog.csdnimg.cn/20181120144104609.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L3FxXzI4MTA5MTcx,size_16,color_FFFFFF,t_70)

参数说明

- compression 打开压缩功能
- compressionMinSize 启用压缩的输出内容大小，这里面默认为2KB
- compressableMimeType 压缩类型
- connectionTimeout 定义建立客户连接超时的时间. 如果为 -1, 表示不限制建立客户连接的时间

### IO优化

![在这里插入图片描述](https://img-blog.csdnimg.cn/20181120144740303.png)

说明
1:同步阻塞IO（JAVA BIO） 同步并阻塞，服务器实现模式为一个连接一个线程(one connection one thread 想想都觉得恐怖,线程可是非常宝贵的资源)，当然可以通过线程池机制改善.
2:JAVA NIO:又分为同步非阻塞IO,异步阻塞IO 与BIO最大的区别one request one thread.可以复用同一个线程处理多个connection(多路复用).
3:,异步非阻塞IO(Java NIO2又叫AIO) 主要与NIO的区别主要是操作系统的底层区别.可以做个比喻:比作快递，NIO就是网购后要自己到官网查下快递是否已经到了(可能是多次)，然后自己去取快递；AIO就是快递员送货上门了(不用关注快递进度)。
BIO方式适用于连接数目比较小且固定的架构，这种方式对服务器资源要求比较高，并发局限于应用中，JDK1.4以前的唯一选择，但程序直观简单易理解.
NIO方式适用于连接数目多且连接比较短（轻操作）的架构，比如聊天服务器，并发局限于应用中，编程比较复杂，JDK1.4开始支持.
AIO方式使用于连接数目多且连接比较长（重操作）的架构，比如相册服务器，充分调用OS参与并发操作，编程比较复杂，JDK7开始支持.

### 开启线程池

配置

![在这里插入图片描述](https://img-blog.csdnimg.cn/20181120145457967.png)

![在这里插入图片描述](https://img-blog.csdnimg.cn/20181120145441570.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L3FxXzI4MTA5MTcx,size_16,color_FFFFFF,t_70)


参数说明

- name：线程池名称，用于 Connector中指定。
- namePrefix：所创建的每个线程的名称前缀，一个单独的线程名称为 
- namePrefix+threadNumber。
- maxThreads：池中最大线程数。
- minSpareThreads：活跃线程数，也就是核心池线程数，这些线程不会被销毁，会一直存在。
- maxIdleTime：线程空闲时间，超过该时间后，空闲线程会被销毁，默认值为6000（1分钟），单位毫秒。
- maxQueueSize：在被执行前最大线程排队数目，默认为Int的最大值，也就是广义的无限。除非特殊情况，这个值不需要更改，否则会有请求不会被处理的情况发生。
- prestartminSpareThreads：启动线程池时是否启动 minSpareThreads部分线程。默认值为false，即不启动。
- threadPriority：线程池中线程优先级，默认值为5，值从1到10。
- className：线程池实现类，未指定情况下，默认实现类为
- org.apache.catalina.core.StandardThreadExecutor。如果想使用自定义线程池首先需要实现 
- org.apache.catalina.Executor接口。

### 添加Listener

另一个影响Tomcat 性能的因素是内存泄露。Server标签中可以配置多个Listener，其中 JreMemoryLeakPreventionListener是用来预防JRE内存泄漏。此Listener只需在Server标签中配置即可，默认情况下无需配置，已经添加在 Server中。![在这里插入图片描述](https://img-blog.csdnimg.cn/2018112014571284.png)

### 组件优化

APR(Apache Portable Runtime)是一个高可移植库，它是Apache HTTP Server 2.x的核心。APR有很多用途，包括访问高级 IO功能(例如sendfile,epoll和OpenSSL)，OS级别功能(随机数生成，系统状态等等)，本地进程管理(共享内存，NT管道和UNIX sockets)。这些功能可以使Tomcat作为一个通常的前台WEB服务器，能更好地和其它本地web技术集成，总体上让Java更有效率作为一个高性能web服务器平台而不是简单作为后台容器。
APR的目的如其名称一样，主要为上层的应用程序提供一个可以跨越多操作系统平台使用的底层支持接口库。在早期的Apache版本中，应用程序本身必须能够处理各种具体操作系统平台的细节，并针对不同的平台调用不同的处理函数。随着Apache的进一步开发，Apache组织决定将这些通用的函数独立出来并发展成为一个新的项目。这样，APR的开发就从Apache中独立出来，Apache仅仅是使用APR而已。目前APR主要还是由Apache使用，不过由于APR的较好的移植性，因此一些需要进行移植的C程序也开始使用APR。
APR使得平台细节的处理进行下移。对于应用程序而言，它们根本就不需要考虑具体的平台，不管是Unix、linux还是Window，应用程序执行的接口基本都是统一一致的。因此对于APR而言，可移植性和统一的上层接口是其考虑的一个重点。而APR最早的目的并不是如此，它最早只是希望将Apache中用到的所有代码合并为一个通用的代码库，然而这不是一个正确的策略，因此后来APR改变了其目标。有的时候使用公共代码并不是一件好事，比如如何将一个请求映射到线程或者进程是平台相关的，因此仅仅一个公共的代码库并不能完成这种区分。APR的目标则是希望安全合并所有的能够合并的代码而不需要牺牲性能。

### Tomcat Native

Tomcat Native是 Tomcat可选组件，它可以让 Tomcat使用 Apache 的 APR包来处理包括文件和网络IO操作，从而提升性能及兼容性。

### 配置

打开conf/server.xml文件，修改Connector 标志的protocol属性：

```
protocol="org.apache.coyote.http11.Http11AprProtocol" 
```


然后添加Listener：

```
 <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />  
```