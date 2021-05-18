此三个命令都会使node停止被调度，后期创建的pod不会继续被调度到该节点上，但操作的暴力程度不一

## cordon 停止调度

影响最小，只会将node调为SchedulingDisabled，之后再发创建pod，不会被调度到该节点，旧有的pod不会受到影响，仍正常对外提供服务

```bash
kubectl cordon node_name
```

恢复调度

```bash
kubectl uncordon node_name
```

## drain 驱逐节点

首先，驱逐node上的pod，其他节点重新创建；接着，将节点调为SchedulingDisabled

```bash
kubectl drain --ignore-daemonsets --delete-local-data --force node_name
```

参数：
**--force**
当一些pod不是经 ReplicationController, ReplicaSet, Job, DaemonSet 或者 StatefulSet 管理的时候，需要用--force来强制执行 (例如:kube-proxy)

**--ignore-daemonsets**
无视DaemonSet管理下的Pod

**--delete-local-data**
如果有mount local volumn的pod，会强制杀掉该pod并清除掉文件，另外如果跟本身的配置讯息有冲突时，drain就不会执行

恢复调度

```bash
kubectl uncordon node_name
```

## delete 删除节点

首先，驱逐node上的pod，其他节点重新创建，然后从master节点删除该node，master对其不可见，失去对其控制，master不可对其恢复

```bash
kubectl delete node_name
```

恢复调度，需进入node节点，重启kubelet，基于node的自注册功能，节点重新恢复使用

```bash
systemctl restart kubelet
```

delete是一个比较粗暴的命令，它会将被删node上的pod直接驱逐，由其他node创建，然后将被删节点从master管理范围内移除，master对其失去管理控制，若想使node重归麾下，必须在node节点重启kubelet

