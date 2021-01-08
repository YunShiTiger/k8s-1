[下载源码](https://github.com/Netflix/eureka/tags)

```bash
wget https://github.com/Netflix/eureka/archive/v1.10.11.zip
unzip v1.10.11.zip
cd eureka-1.10.11
```

修改配置文件

```bash
cat<< 'EOF' >eureka-server/src/main/resources/eureka-server.properties
#注册中心名
spring.application.name=eureka-server
#服务注册中心端口号
server.port=8888
#触发自我保护机制的阀值配置信息时间
eureka.server.renewal-percent-threshold=0.9
#关闭保护机
eureka.server.enable-self-preservation=false
#扫描失效服务的间隔时间
eureka.server.eviction-interval-timer-in-ms=40000
#服务注册中心实例的主机名
eureka.instance.hostname=localhost
#是否向服务注册中心注册自己
eureka.instance.prefer-ip-address=false
#禁止自己当做服务注册
eureka.client.register-with-eureka=true
#是否检索服务
eureka.client.fetch-registry=true
#服务注册中心的配置内容，指定服务注册中心的位置
eureka.client.serviceUrl.defaultZone=http://eureka-0.eureka.infra.svc.cluster.local:${server.port}/eureka,http://eureka-1.eureka.infra.svc.cluster.local:${server.port}/eureka,http://eureka-2.eureka.infra.svc.cluster.local:${server.port}/eureka
EOF
```

构建Eureka Server

```bash
./installViaTravis.sh --warning-mode all
```

构建成功后，生成jar与war包，可以java -jar起，也可以用tomcat起

```
[root@supper eureka-1.10.11]# ll eureka-server/build/libs
total 21604
-rw-r--r-- 1 root root     1029 Jan  6 23:18 eureka-server-0.1.0-dev.0.uncommitted-javadoc.jar
-rw-r--r-- 1 root root 22117347 Jan  6 23:19 eureka-server-0.1.0-dev.0.uncommitted.war
```

