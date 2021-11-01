

## centOS 升级内核版本

```bash
#检查当前 CentOS 系统版本
cat /etc/redhat-release
> CentOS Linux release 7.1.1503 (Core)
检查当前 CentOS 系统内核版本
uname -sr
> Linux 3.10.0-1127.13.1.el7.x86_64
```

升级 CentOS 7.× 内核,启用 ELRepo

```bash
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
```

生成缓存

```bash
yum makecache fast
```

仓库启用后，你可以使用下面的命令列出可用的系统内核相关包:

```bash
yum --disablerepo="*" --enablerepo="elrepo-kernel" list available

Available Packages                        
kernel-lt.x86_64                                                 4.4.239-1.el7.elrepo                       
kernel-lt-devel.x86_64                                           4.4.239-1.el7.elrepo                       
kernel-lt-doc.noarch                                             4.4.239-1.el7.elrepo                       
kernel-lt-headers.x86_64                                         4.4.239-1.el7.elrepo                       
kernel-lt-tools.x86_64                                           4.4.239-1.el7.elrepo                       
kernel-lt-tools-libs.x86_64                                      4.4.239-1.el7.elrepo                       
kernel-lt-tools-libs-devel.x86_64                                4.4.239-1.el7.elrepo                       
kernel-ml.x86_64                                                 5.9.0-1.el7.elrepo                         
kernel-ml-devel.x86_64                                           5.9.0-1.el7.elrepo                         
kernel-ml-doc.noarch                                             5.9.0-1.el7.elrepo                         
kernel-ml-headers.x86_64                                         5.9.0-1.el7.elrepo                         
kernel-ml-tools.x86_64                                           5.9.0-1.el7.elrepo                         
kernel-ml-tools-libs.x86_64                                      5.9.0-1.el7.elrepo                         
kernel-ml-tools-libs-devel.x86_64                                5.9.0-1.el7.elrepo                         
```

**安装内核**

在yum的ELRepo源中，有mainline颁布的，可以这样安装：

```bash
yum --enablerepo=elrepo-kernel install  kernel-ml* --skip-broken -y
```

当然也可以安装long term的：

```bash
yum --enablerepo=elrepo-kernel  install  kernel-lt* --skip-broken -y
```

**设置 GRUB 默认的内核版本**
设置新安装的内核成为默认启动项，初始化页面时第一个内核将作为默认内核,需修改/etc/default/grub, 设置 GRUB_DEFAULT=0.

```bash
sed -ri "s#(^GRUB_DEFAULT=)(.*)#\10#g" /etc/default/grub
cat /etc/default/grub

GRUB_TIMEOUT=1
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=0 #设置 GRUB 默认的内核版本
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --speed=115200"
GRUB_CMDLINE_LINUX="console=tty0 crashkernel=auto console=ttyS0,115200"
GRUB_DISABLE_RECOVERY="true"
```

重新创建内核配置.

```bash
grub2-mkconfig -o /boot/grub2/grub.cfg
```

查看内核

```bash
[root@supper ~]# rpm -qa|grep ^kernel
kernel-lt-4.4.240-1.el7.elrepo.x86_64
kernel-3.10.0-1127.19.1.el7.x86_64
kernel-headers-3.10.0-1127.19.1.el7.x86_64
kernel-3.10.0-1127.el7.x86_64
kernel-devel-3.10.0-1127.19.1.el7.x86_64
kernel-devel-3.10.0-1127.el7.x86_64
kernel-tools-libs-3.10.0-1127.19.1.el7.x86_64
kernel-tools-3.10.0-1127.19.1.el7.x86_64
```

要卸载的内核

```bash
rpm -qa|grep ^kernel|grep 3.10.0
```

卸载内核

```bash
for n in `rpm -qa|grep ^kernel|grep 3.10.0`;do yum remove -y $n;done
```

**再重装一遍内核**

mainline源

```bash
yum --enablerepo=elrepo-kernel install  kernel-ml* --skip-broken -y
```

long term源

```
yum --enablerepo=elrepo-kernel  install  kernel-lt* --skip-broken -y
```

**重启系统**

```bash
reboot
```

卸载内核

```bash
for n in `rpm -qa|grep ^kernel|grep 3.10.0`;do yum remove -y $n;done
```

查看系统当前内核版本,验证最新的内核已作为默认内核

```bash
uname -a
> Linux localhost.localdomain 5.9.0-1.el7.elrepo.x86_64 #1 SMP Sun Oct 11 17:57:16 EDT 2020 x86_64 x86_64 x86_64 GNU/Linux
```

