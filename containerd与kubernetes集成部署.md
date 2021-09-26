# 前言

nerdctl 是一个与 docker cli 风格兼容的 containerd 客户端工具，而且直接兼容 docker compose 的语法的，这就大大提高了直接将 containerd 作为本地开发、测试或者单机容器部署使用的效率。

# 部署环境

```bash
# 操作系统： CentOS Linux 7 (Core)
# kubelet 版本： v1.18.14
# containerd版本：1.5.5
# nerdctl 版本：0.11.2
# cni版本：0.9.1
# runc版本：1.0.2
# 工作目录：/opt/containerd
# 二进制文件目录：/usr/local/bin
# cni 目录：/opt/cni
```

# 准备所需二进制文件

下载crictl

```bash
wget https://github.com/containerd/nerdctl/releases/download/v0.11.2/nerdctl-0.11.2-linux-amd64.tar.gz
```

下载containerd

```bash
wget https://github.com/containerd/containerd/releases/download/v1.5.5/containerd-1.5.5-linux-amd64.tar.gz
```

下载runc

```bash
wget https://github.com/opencontainers/runc/releases/download/v1.0.2/runc.amd64 -O /usr/bin/runc && chmod +x /usr/bin/runc 
```

下载cni

```bash
wget https://github.com/containernetworking/plugins/releases/download/v0.9.1/cni-plugins-linux-amd64-v0.9.1.tgz
```

# 解压下载文件到相应的目录

```bash
# containerd 解压
tar -xvf containerd-1.5.5-linux-amd64.tar.gz -C /usr/local
# nerdctl 解压
tar -xvf nerdctl-0.11.2-linux-amd64.tar.gz -C /usr/local/bin/
# cni 解压
tar -xvf cni-plugins-linux-amd64-v0.9.1.tgz -C /opt/cni/bin/
```

# 准备配置文件

```bash
mkdir -p /opt/containerd/etc
```

containerd 配置文件准备

```bash
containerd config default >/opt/containerd/etc/config.toml
```

修改默认的 pause 镜像为国内的地址，替换 `[plugins."io.containerd.grpc.v1.cri"]` 下面的 `sandbox_image`：

```bash
[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "registry.aliyuncs.com/k8sxio/pause:3.2"
```

同样再配置下镜像仓库的加速器地址：

```bash
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
          endpoint = ["https://bqr1dr1n.mirror.aliyuncs.com"]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."k8s.gcr.io"]
          endpoint = ["https://registry.aliyuncs.com/k8sxio"]
```

# 准备containerd 启动文件

由于先前已经安装了docker containerd.service 文件已经存在，为了保证docker 正常运行,新安装的修改为container

```bash
cat << EOF >/usr/lib/systemd/system/containerd.service
[Unit]
Description=Lightweight Kubernetes
Documentation=https://containerd.io
After=network-online.target
[Service]
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStartPre=-/bin/mkdir -p /run/containerd
ExecStart=/usr/local/bin/containerd \\
         -c /opt/containerd/etc/config.toml \\
         -a /run/containerd/containerd.sock \\
         --state /opt/containerd/run/containerd \\
         --root /opt/containerd/root
KillMode=process
Delegate=yes
OOMScoreAdjust=-999
LimitNOFILE=1024000
LimitNPROC=1024000
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
```

# 启动containerd

```bash
systemctl enable --now containerd.service
```

# 验证containerd 部署是否正常

拉取镜像测试

```bash
[root@k8s ~]# nerdctl pull busybox:1.28
docker.io/library/busybox:1.28:                                                   resolved       |++++++++++++++++++++++++++++++++++++++| 
index-sha256:141c253bc4c3fd0a201d32dc1f493bcf3fff003b6df416dea4f41046e0f37d47:    done           |++++++++++++++++++++++++++++++++++++++| 
manifest-sha256:74f634b1bc1bd74535d5209589734efbd44a25f4e2dc96d78784576a3eb5b335: done           |++++++++++++++++++++++++++++++++++++++| 
config-sha256:8c811b4aec35f259572d0f79207bc0678df4c736eeec50bc9fec37ed936a472a:   done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:07a152489297fc2bca20be96fab3527ceac5668328a30fd543a160cd689ee548:    done           |++++++++++++++++++++++++++++++++++++++| 
elapsed: 5.5 s 
```

查看镜像

```bash
[root@k8s ~]# nerdctl images
REPOSITORY    TAG     IMAGE ID        CREATED           SIZE
busybox       1.28    141c253bc4c3    44 seconds ago    1.1 MiB
```

# kubelet 配置文件以支持containerd

```bash
cat<< 'EOF' >/usr/lib/systemd/system/kubelet.service 
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=docker.service
Requires=docker.service
[Service]
ExecStartPre=-/bin/mkdir -p /sys/fs/cgroup/hugetlb/systemd/system.slice/kubelet.service
ExecStartPre=-/bin/mkdir -p /sys/fs/cgroup/blkio/systemd/system.slice/kubelet.service
ExecStartPre=-/bin/mkdir -p /sys/fs/cgroup/cpuset/systemd/system.slice/kubelet.service
ExecStartPre=-/bin/mkdir -p /sys/fs/cgroup/devices/systemd/system.slice/kubelet.service
ExecStartPre=-/bin/mkdir -p /sys/fs/cgroup/net_cls,net_prio/systemd/system.slice/kubelet.service
ExecStartPre=-/bin/mkdir -p /sys/fs/cgroup/perf_event/systemd/system.slice/kubelet.service
ExecStartPre=-/bin/mkdir -p /sys/fs/cgroup/cpu,cpuacct/systemd/system.slice/kubelet.service
ExecStartPre=-/bin/mkdir -p /sys/fs/cgroup/freezer/systemd/system.slice/kubelet.service
ExecStartPre=-/bin/mkdir -p /sys/fs/cgroup/memory/systemd/system.slice/kubelet.service
ExecStartPre=-/bin/mkdir -p /sys/fs/cgroup/pids/systemd/system.slice/kubelet.service
ExecStartPre=-/bin/mkdir -p /sys/fs/cgroup/systemd/systemd/system.slice/kubelet.service
ExecStart=/opt/kubernetes/bin/kubelet \
--alsologtostderr=true \
--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.kubeconfig \
--cert-dir=/etc/kubernetes/pki \
--cni-bin-dir=/opt/cni/bin \
--cni-conf-dir=/etc/cni/net.d \
--config=/etc/kubernetes/kubelet.yaml \
--container-runtime=remote \
--container-runtime-endpoint=unix:///run/containerd/containerd.sock \
--containerd=unix:///run/containerd/containerd.sock \
--image-pull-progress-deadline=30s \
--kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
--log-dir=/data/kubernetes/logs \
--logtostderr=false \
--network-plugin=cni \
--root-dir=/etc/kubernetes/kubelet \
--runtime-cgroups=/systemd/system.slice \
--volume-plugin-dir=/etc/kubernetes/kubelet-plugins \
--v=2
Restart=always
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
```

# 重启kubelet

```bash
systemctl daemon-reload && systemctl restart kubelet
```

# 查看状态

```bash
systemctl status kubelet
```

# 验证kubelet 是否使用containerd

```bash
[root@k8s ~]# nerdctl ps
CONTAINER           IMAGE         CREATED        STATE      NAME                   ATTEMPT    POD ID
58f5c70340b3a       9a07b5b4bfac0 2 minutes ago Running   kubernetes-dashboard        0     d04d56936f965
2035953e03985       8d147537fb7d1 2 minutes ago Running   coredns                     0     b69f5c6efb7ff
856c49d881a8c       48d79e554db69 2 minutes ago Running   dashboard-metrics-scraper   0     77ef8c6d65589
c34e3f9016528       9dd718864ce61 3 minutes ago Running   metrics-server              0     56e9704fe1770
```

# nerdctl使用

### Run&Exec

**🐳nerdctl run**

和 `docker run` 类似可以使用 `nerdctl run` 命令运行容器，例如：

```bash
[root@k8s ~]# nerdctl run -d -p 80:80 --name=nginx --restart=always nginx:alpine
docker.io/library/nginx:alpine:                                                   resolved       |++++++++++++++++++++++++++++++++++++++| 
index-sha256:686aac2769fd6e7bab67663fd38750c135b72d993d0bb0a942ab02ef647fc9c3:    done           |++++++++++++++++++++++++++++++++++++++| 
manifest-sha256:af466e4f12e3abe41fcfb59ca0573a3a5c640573b389d5287207a49d1324abd8: done           |++++++++++++++++++++++++++++++++++++++| 
config-sha256:513f9a9d8748b25cdb0ec6f16b4523af7bba216a6bf0f43f70af75b4cf7cb780:   done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:61074acc7dd227cfbeaf719f9b5cdfb64711bc6b60b3865c7b886b7099c15d15:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:c1368e94e1ec563b31c3fb1fea02c9fbdc4c79a95e9ad0cac6df29c228ee2df3:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:3e72c40d0ff43c52c5cc37713b75053e8cb5baea8e137a784d480123814982a2:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:a0d0a0d46f8b52473982a3c466318f479767577551a53ffc9074c9fa7035982e:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:4dd4efe90939ab5711aaf5fcd9fd8feb34307bab48ba93030e8b845f8312ed8e:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:969825a5ca61c8320c63ff9ce0e8b24b83442503d79c5940ba4e2f0bd9e34df8:    done           |++++++++++++++++++++++++++++++++++++++| 
elapsed: 12.2s                                                                    total:  9.5 Mi (798.4 KiB/s)                                     
a22335a452eb03b0c4be3fa601d4a3a498ed0ce00d83a18ec8f2ccd5327a2f35
```

可选的参数使用和 `docker run` 基本一致，比如 `-i`、`-t`、`--cpus`、`--memory` 等选项，可以使用 `nerdctl run --help` 获取可使用的命令选项：

```bash
[root@k8s ~]# nerdctl run --help
NAME:
   nerdctl run - Run a command in a new container

USAGE:
   nerdctl run [command options] [arguments...]

OPTIONS:
   --help                        show help (default: false)
   --tty, -t                     (Currently -t needs to correspond to -i) (default: false)
   --interactive, -i             Keep STDIN open even if not attached (default: false)
   --detach, -d                  Run container in background and print container ID (default: false)
   --restart value               Restart policy to apply when a container exits (implemented values: "no"|"always") (default: "no")
   --rm                          Automatically remove the container when it exits (default: false)
   --pull value                  Pull image before running ("always"|"missing"|"never") (default: "missing")
   --network value, --net value  Connect a container to a network ("bridge"|"host"|"none") (default: "bridge")
   --dns value                   Set custom DNS servers (default: "8.8.8.8", "1.1.1.1")
   --publish value, -p value     Publish a container's port(s) to the host
   --hostname value, -h value    Container host name
   --cpus value                  Number of CPUs (default: 0)
   --memory value, -m value      Memory limit
   --pid value                   PID namespace to use
   --pids-limit value            Tune container pids limit (set -1 for unlimited) (default: -1)
   --cgroupns value              Cgroup namespace to use, the default depends on the cgroup version ("host"|"private") (default: "host")
   --cpuset-cpus value           CPUs in which to allow execution (0-3, 0,1)
   --cpu-shares value            CPU shares (relative weight) (default: 0)
   --device value                Add a host device to the container
   --user value, -u value        Username or UID (format: <name|uid>[:<group|gid>])
   --security-opt value          Security options
   --cap-add value               Add Linux capabilities
   --cap-drop value              Drop Linux capabilities
   --privileged                  Give extended privileges to this container (default: false)
   --runtime value               Runtime to use for this container, e.g. "crun", or "io.containerd.runsc.v1" (default: "io.containerd.runc.v2")
   --sysctl value                Sysctl options
   --gpus value                  GPU devices to add to the container ('all' to pass all GPUs)
   --volume value, -v value      Bind mount a volume
   --read-only                   Mount the container's root filesystem as read only (default: false)
   --rootfs                      The first argument is not an image but the rootfs to the exploded container (default: false)
   --entrypoint value            Overwrite the default ENTRYPOINT of the image
   --workdir value, -w value     Working directory inside the container
   --env value, -e value         Set environment variables
   --add-host value              Add a custom host-to-IP mapping (host:ip)
   --env-file value              Set environment variables from file
   --name value                  Assign a name to the container
   --label value, -l value       Set meta data on a container
   --label-file value            Read in a line delimited file of labels
   --cidfile value               Write the container ID to the file
   --shm-size value              Size of /dev/shm
   --pidfile value               file path to write the task's pid
```

**🐳nerdctl exec**

同样也可以使用 `exec` 命令执行容器相关命令，例如：

```bash
[root@k8s ~]# nerdctl exec -it nginx /bin/sh
/ # date
Sun Sep 26 09:56:14 UTC 2021
```

### 容器管理

**🐳nerdctl ps**：列出容器

使用 `nerdctl ps` 命令可以列出所有容器。

```bash
[root@k8s ~]# nerdctl ps
CONTAINER ID    IMAGE                             COMMAND                   CREATED           STATUS    PORTS                 NAMES
6a8d2de90c6e    docker.io/library/nginx:alpine    "/docker-entrypoint.…"    24 seconds ago    Up        0.0.0.0:80->80/tcp    nginx
```

同样可以使用 `-a` 选项显示所有的容器列表，默认只显示正在运行的容器，不过需要注意的是 `nerdctl ps` 命令并没有实现 `docker ps` 下面的 `--filter`、`--format`、`--last`、`--size` 等选项。

**🐳nerdctl inspect**：获取容器的详细信息。

```bash
[root@k8s ~]# nerdctl inspect nginx
[
    {
        "Id": "a22335a452eb03b0c4be3fa601d4a3a498ed0ce00d83a18ec8f2ccd5327a2f35",
        "Created": "2021-09-26T09:55:05.020017161Z",
        "Path": "/docker-entrypoint.sh",
        "Args": [
            "nginx",
            "-g",
            "daemon off;"
        ],
        "State": {
            "Status": "running",
            "Running": true,
            "Paused": false,
            "Pid": 29301,
            "ExitCode": 0,
            "FinishedAt": "0001-01-01T00:00:00Z"
        },
        "Image": "docker.io/library/nginx:alpine",
        "ResolvConfPath": "*",
        "LogPath": "*",
        "Name": "nginx",
        "Driver": "overlayfs",
        "Platform": "linux",
        "AppArmorProfile": "",
        "NetworkSettings": {
            "Ports": {
                "80/tcp": [
                    {
                        "HostIp": "0.0.0.0",
                        "HostPort": "80"
                    }
                ]
            },
            "GlobalIPv6Address": "",
            "GlobalIPv6PrefixLen": 0,
            "IPAddress": "10.4.0.7",
            "IPPrefixLen": 24,
            "MacAddress": "26:d3:d3:67:6b:6d",
            "Networks": {
                "unknown-eth0": {
                    "IPAddress": "10.4.0.7",
                    "IPPrefixLen": 24,
                    "GlobalIPv6Address": "",
                    "GlobalIPv6PrefixLen": 0,
                    "MacAddress": "26:d3:d3:67:6b:6d"
                }
            }
        }
    }
]
```

可以看到显示结果和 `docker inspect` 也基本一致的。

**🐳nerdctl logs**：获取容器日志

查看容器日志是我们平时经常会使用到的一个功能，同样我们可以使用 `nerdctl logs` 来获取日志数据：

```bash
[root@k8s ~]# nerdctl logs -f nginx
......
2021/08/19 06:35:46 [notice] 1#1: start worker processes
2021/08/19 06:35:46 [notice] 1#1: start worker process 32
2021/08/19 06:35:46 [notice] 1#1: start worker process 33
```

同样支持 `-f`、`-t`、`-n`、`--since`、`--until` 这些选项。

**🐳nerdctl stop**：停止容器

```bash
[root@k8s ~]# nerdctl stop nginx
nginx
```

**🐳nerdctl rm**：删除容器

```bash
[root@k8s ~]# nerdctl rm -f nginx
nginx
```

要强制删除同样可以使用 `-f` 或 `--force` 选项来操作。

### 镜像管理

**🐳nerdctl images**：镜像列表

```bash
[root@k8s ~]# nerdctl images
REPOSITORY    TAG       IMAGE ID        CREATED          SIZE
nginx         alpine    686aac2769fd    5 minutes ago    24.9 MiB
```

也需要注意的是没有实现 `docker images` 的一些选项，比如 `--all`、`--digests`、`--filter`、`--format`。

**🐳nerdctl pull**：拉取镜像

```bash
[root@k8s ~]# nerdctl image rm nginx:alpine
Untagged: docker.io/library/nginx:alpine@sha256:686aac2769fd6e7bab67663fd38750c135b72d993d0bb0a942ab02ef647fc9c3
Deleted: sha256:e2eb06d8af8218cfec8210147357a68b7e13f7c485b991c288c2d01dc228bb68
Deleted: sha256:e6d3cea19fef0752dc05de747d53678768e5442b7bc553da24c26843fb004991
Deleted: sha256:20d0effdf3a238c529aef35de8ec8ad77705b85a36f46e3176bba4178bceaddf
Deleted: sha256:311d8db33235c961c2327f4ffdd3ffcdfbd752261b10546bc5aa77ae3e3a52be
Deleted: sha256:b4b4e85910eaa882511fa86afc141b08e8d04681f061c099c47a072036dcb7a3
Deleted: sha256:40403bebe4fddeee2a651217032b0bae844ff0a4a5fbcb4b646d8f4f20cff0b1
```

**🐳nerdctl push**：推送镜像

当然在推送镜像之前也可以使用 `nerdctl login` 命令登录到镜像仓库，然后再执行 push 操作。

可以使用 `nerdctl login --username xxx --password xxx` 进行登录，使用 `nerdctl logout` 可以注销退出登录。

**🐳nerdctl tag**：镜像标签

使用 `tag` 命令可以为一个镜像创建一个别名镜像：

```bash
[root@k8s ~]# nerdctl images
REPOSITORY    TAG                  IMAGE ID        CREATED           SIZE
busybox       latest               0f354ec1728d    6 minutes ago     1.3 MiB
nginx         alpine               bead42240255    41 minutes ago    16.0 KiB
[root@k8s ~]# nerdctl tag nginx:alpine harbor.k8s.local/course/nginx:alpine
[root@k8s ~]# nerdctl images
REPOSITORY                       TAG                  IMAGE ID        CREATED           SIZE
busybox                          latest               0f354ec1728d    7 minutes ago     1.3 MiB
nginx                            alpine               bead42240255    41 minutes ago    16.0 KiB
harbor.k8s.local/course/nginx    alpine               bead42240255    2 seconds ago     16.0 KiB
```

**🐳nerdctl save**：导出镜像

使用 `save` 命令可以导出镜像为一个 `tar` 压缩包。

```bash
[root@k8s ~]# nerdctl save -o busybox.tar.gz busybox:latest
[root@k8s ~]# ll
total 764
-rw-r--r-- 1 root root 779776 Sep 26 23:55 busybox.tar.gz
```

**🐳nerdctl rmi**：删除镜像

```bash
[root@k8s ~]# nerdctl rmi busybox
Untagged: docker.io/library/busybox:latest@sha256:f7ca5a32c10d51aeda3b4d01c61c6061f497893d7f6628b92f822f7117182a57
Deleted: sha256:cfd97936a58000adc09a9f87adeeb7628a2c71d11c4998e6e7f26935fa0cd713
```

**🐳nerdctl load**：导入镜像

使用 `load` 命令可以将上面导出的镜像再次导入：

```bash
[root@k8s ~]# nerdctl load -i busybox.tar.gz
unpacking docker.io/library/busybox:latest (sha256:f7ca5a32c10d51aeda3b4d01c61c6061f497893d7f6628b92f822f7117182a57)...done
unpacking overlayfs@sha256:f7ca5a32c10d51aeda3b4d01c61c6061f497893d7f6628b92f822f7117182a57 (sha256:f7ca5a32c10d51aeda3b4d01c61c6061f497893d7f6628b92f822f7117182a57)...done
```

使用 `-i` 或 `--input` 选项指定需要导入的压缩包。

### 镜像构建

镜像构建是平时我们非常重要的一个需求，我们知道 `ctr` 并没有构建镜像的命令，而现在我们又不使用 Docker 了，那么如何进行镜像构建了，幸运的是 `nerdctl` 就提供了 `nerdctl build` 这样的镜像构建命令。

**🐳nerdctl build**：从 Dockerfile 构建镜像

比如现在我们定制一个 nginx 镜像，新建一个如下所示的 Dockerfile 文件：

```bash
cat << EOF >Dockerfile
FROM nginx
RUN echo '这是一个基于containerd使用nerdctl构建的nginx镜像' > /usr/share/nginx/html/index.html
EOF
```

然后在文件所在目录执行镜像构建命令：

```bash
[root@k8s ~]# nerdctl build -t nginx:nerdctl -f Dockerfile .
FATA[0000] `buildctl` needs to be installed and `buildkitd` needs to be running, see https://github.com/moby/buildkit: exec: "buildctl": executable file not found in $PATH
```

可以看到有一个错误提示，需要我们安装 `buildctl` 并运行 `buildkitd`，这是因为 `nerdctl build` 需要依赖 `buildkit` 工具。

buildkit 项目也是 Docker 公司开源的一个构建工具包，支持 OCI 标准的镜像构建。它主要包含以下部分:

- 服务端 `buildkitd`：当前支持 runc 和 containerd 作为 worker，默认是 runc，我们这里使用 containerd
- 客户端 `buildctl`：负责解析 Dockerfile，并向服务端 buildkitd 发出构建请求

buildkit 是典型的 C/S 架构，客户端和服务端是可以不在一台服务器上，而 `nerdctl` 在构建镜像的时候也作为 `buildkitd` 的客户端，所以需要我们安装并运行 `buildkitd`。

所以接下来我们先来安装 `buildkit`：

下载buildkit

```bash
wget https://github.com/moby/buildkit/releases/download/v0.9.0/buildkit-v0.9.0.linux-amd64.tar.gz
```

解压

```bash
tar -zxvf buildkit-v0.9.0.linux-amd64.tar.gz -C /usr/local
```

Systemd 来管理 `buildkitd`

```bash
cat<< EOF >/etc/systemd/system/buildkit.service
[Unit]
Description=BuildKit
Documentation=https://github.com/moby/buildkit
[Service]
ExecStart=/usr/local/bin/buildkitd --oci-worker=false --containerd-worker=true
[Install]
WantedBy=multi-user.target
EOF
```

启动 `buildkitd`：

```bash
systemctl daemon-reload && systemctl enable buildkit --now
```

查看状态

```bash
systemctl status buildkit
```

重新构建镜像

```bash
nerdctl build --no-cache -t nginx:nerdctl -f Dockerfile .
```

构建完成后查看镜像是否构建成功：

```bash
[root@k8s ~]# nerdctl images
WARN[0000] unparsable image name "overlayfs@sha256:d5b9b9e4c930f30340650cb373f62f97c93ee3b92c83f01c6e00b7b87d62c624"
REPOSITORY    TAG        IMAGE ID        CREATED               SIZE
nginx         latest     4d4d96ac750a    4 minutes ago         16.0 KiB
nginx         nerdctl    d5b9b9e4c930    About a minute ago    24.0 KiB
                         d5b9b9e4c930    About a minute ago    24.0 KiB
```

我们可以看到已经有我们构建的 `nginx:nerdctl` 镜像了，不过出现了一个 `WARN[0000] unparsable image name "xxx"` 的 Warning 信息，在镜像列表里面也可以看到有一个镜像 tag 为空的镜像，和我们构建的镜像 ID 一样，在 nerdctl 的 github issue 上也有提到这个问题：https://github.com/containerd/nerdctl/issues/177，不过到现在为止还没有 FIX，幸运的是这只是一个⚠️，不会影响我们的使用。

接下来使用上面我们构建的镜像来启动一个容器进行测试：

```bash
[root@k8s ~]# nerdctl run -d -p 80:80 --name=nginx --restart=always nginx:nerdctl
09118d9928d2c2ea94e330b722c64537524c73ce0e3af3b7abbd553bdddeab11

[root@k8s ~]# nerdctl ps
CONTAINER ID    IMAGE                              COMMAND                   CREATED           STATUS    PORTS                 NAMES
09118d9928d2    docker.io/library/nginx:nerdctl    "/docker-entrypoint.…"    17 seconds ago    Up        0.0.0.0:80->80/tcp    nginx

[root@k8s ~]# curl localhost
这是一个基于containerd使用nerdctl构建的nginx镜像
```

这样我们就使用 `nerdctl + buildkitd` 轻松完成了容器镜像的构建。

当然如果你还想在单机环境下使用 Docker Compose，在 containerd 模式下，我们也可以使用 `nerdctl` 来兼容该功能。同样我们可以使用 `nerdctl compose`、`nerdctl compose up`、`nerdctl compose logs`、`nerdctl compose build`、`nerdctl compose down` 等命令来管理 Compose 服务。这样使用 containerd、nerdctl 结合 buildkit 等工具就完全可以替代 docker 在镜像构建、镜像容器方面的管理功能了。