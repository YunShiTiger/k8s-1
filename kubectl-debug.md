## kubectl-debug

kubectl-debug 其实就是一个 kubectl 的插件，他的原理和 docker 容器诊断工具大同小异。kubectl-debug 可以帮我们在 某个 Pod 的节点上起一个容器，并将这个容器加入到目标容器的pid,network,user,icp 的命名空间。kubectl-debug 架构主要可以分为两部分：

- 客户端：kubectl-debug 二进制文件

- 服务端：agent 容器

客户端通过控制 node 上的 agent 服务端与容器运行时通信，从而启动一个容器并进入到指定 Pod 的命名空间，可以说 agent 就是一个 debug 容器与客户端之间的中继。而从 kubectl-debug 的工作模式来看，可以分为两种模式：

- 非常驻服务端：agentless
- 常驻服务端： DaemonSet

简单来说就是 agentless 模式只有在每次 kubectl-debug 进行调试 Pod 的时候才会启动一个 agent 服务端，调试完成后自动清理 agent，此模式的优点是不那么占用 kubernetes 集群资源，而 DaemonSet 模式就是在每个节点上都会常驻一个 DaemonSet 的 agent， 好处就是启动快。
此外针对 node 节点无法直接访问的情况，kubectl-debug 还有一个 port-forward 模式。

### 安装客户端

安装过程和 docker-debug 差不多

下载二进制文件: 

```
wget https://github.com/aylei/kubectl-debug/releases/download/v0.1.0/kubectl-debug_0.1.0_linux_amd64.tar.gz -O kubectl-debug.tar.gz
```

解压文件: tar -zxvf kubectl-debug.tar.gz
安装 agent 服务端[agent_daemonset.yml](https://raw.githubusercontent.com/aylei/kubectl-debug/master/scripts/agent_daemonset.yml)

修改文件

```yaml
cat << 'EOF' >kubectl-debug-ds.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    app: debug-agent
  name: debug-agent
spec:
  selector:
    matchLabels:
      app: debug-agent
  template:
    metadata:
      labels:
        app: debug-agent
    spec:
      hostPID: true
      tolerations:
        - key: node-role.kubernetes.io/master
          effect: NoSchedule
      containers:
        - name: debug-agent
          image: aylei/debug-agent:latest
          imagePullPolicy: Always
          securityContext:
            privileged: true
          livenessProbe:
            failureThreshold: 3
            httpGet:
              path: /healthz
              port: 10027
              scheme: HTTP
            initialDelaySeconds: 10
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 1
          ports:
            - containerPort: 10027
              hostPort: 10027
              name: http
              protocol: TCP
          volumeMounts:
            - name: cgroup
              mountPath: /sys/fs/cgroup
            - name: lxcfs
              mountPath: /var/lib/lxc
              mountPropagation: Bidirectional
            - name: docker
              mountPath: "/var/run/docker.sock"
            - name: runcontainerd
              mountPath: "/run/containerd"
            - name: runrunc
              mountPath: "/run/runc"
            - name: vardata
              mountPath: "/var/data"
      # hostNetwork: true
      volumes:
        - name: cgroup
          hostPath:
            path: /sys/fs/cgroup
        - name: lxcfs
          hostPath:
            path: /var/lib/lxc
            type: DirectoryOrCreate
        - name: docker
          hostPath:
            path: /var/run/docker.sock
        # containerd client will need to access /var/data, /run/containerd and /run/runc
        - name: vardata
          hostPath:
            path: /var/data
        - name: runcontainerd
          hostPath:
            path: /run/containerd
        - name: runrunc
          hostPath:
            path: /run/runc
  updateStrategy:
    rollingUpdate:
      maxUnavailable: 5
    type: RollingUpdate
EOF
```

创建 DaemonSet：

```bash
kubectl apply -f kubectl-debug-ds.yaml
```

可以看到每个节点上都创建了 debug-agent 的 DaemonSet，并且宿主机上都监听了10027端口。

```
[root@manage ~]# kubectl get pods
NAME                                      READY   STATUS    RESTARTS   AGE
debug-agent-796vb                         1/1     Running   0          86s
debug-agent-gtxkd                         1/1     Running   0          87s
```


执行命令kubectl-debug <POD_NAME>就可以进行调试了

![image-20200704202743105](k8s/upload/image-20200704202743105.png)
我们可以看到已经进入了目标容器的命名空间了

 kubectl 1.12.0 或更高的版本, 可以直接使用:

```
kubectl-debug -h
```

老版本的 kubectl 无法自动发现插件, 需要直接调用 binary

```
kubect-debug POD_NAME
```

假如安装了 debug-agent 的 daemonset, 可以略去 --agentless 来加快启动速度
之后的命令里会略去 --agentless

```
kubectl debug POD_NAME --agentless
```

假如 Pod 处于 CrashLookBackoff 状态无法连接, 可以复制一个完全相同的 Pod 来进行诊断

```
kubectl debug POD_NAME --fork
```

假如 Node 没有公网 IP 或无法直接访问(防火墙等原因), 请使用 port-forward 模式

```
kubectl debug POD_NAME --port-forward --daemonset-ns=kube-system --daemonset-name=debug-agent
```

**进阶使用：**

排错init-container：

```javascript
kubectl debug demo-pod --container=init-pod
```

排错crash pod：

```javascript
kubectl debug POD_NAME --fork
```

离线配置：

--image：可自定义排错工具容器镜像，改为私有镜像仓库，默认为nicolaka/netshoot:latest

诊断 CrashLoopBackoff

```bash
# 进入调试容器
$ kubectl debug -n dev ****-8589cdd7bb-zhsz6 --fork -a
# 进入服务容器
$ chroot /proc/1/root
# 启动服务
$ ./entrypoint.sh
```