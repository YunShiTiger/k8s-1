## 1、k8s容器资源限制

k8s采用request和limit两种限制类型来对资源进行分配

- request(资源需求)：即运行pod的节点必须满足运行pod的最基本需求才能运行pod。
- limit(资源限制)：即运行pod期间，可能内存使用量会增加，那最多能使用多少内存，这就是资源限额。

资源类型：

- CPU的单位是核心数，内存的单位是字节。
- 一个容器申请0.5各CPU，就相当于申请1个CPU的一半，可以加个后缀m表示千分之一的概念。比如说100m的CPU，100豪的CPU和0.1个CPU都是一样的。

内存单位：

- K，M，G，T，P，E #通常是以1000为换算标准的。Ki，Mi，Gi，Ti，Pi，Ei #通常是以1024为换算标准的。

## 2、内存资源限制实例

```yaml
cat<< EOF >limit-memory-pod.yaml
apiVersion: apps/v1
kind: Deployment
metadata:  
  name: memory-demo
spec:  
  replicas: 1
  selector:    
    matchLabels:      
      app: memory-demo  
  template:    
    metadata:      
      labels:        
        app: memory-demo    
    spec:      
      containers:      
      - name: memory-demo        
        image: progrium/stress:latest
        args:
        - --vm
        - "1"
        - --vm-bytes
        - 200M           #容器使用200M
        resources:
          requests:      #资源需求，下限 
            memory: 50Mi
          limits:        #资源限制，上限
            memory: 100Mi
EOF
kubectl apply -f limit-memory-pod.yaml
```

查看状态

```bash
[root@supper ~]# kubectl get pod
NAME                          READY   STATUS             RESTARTS   AGE
memory-demo-8df545dc9-27tjj   0/1     CrashLoopBackOff   1          2m44s
```

查看日志

```yaml
[root@supper ~]# kubectl logs memory-demo-8df545dc9-fsg57
stress: FAIL: [1] (416) <-- worker 8 got signal 9
stress: WARN: [1] (418) now reaping child worker processes
stress: FAIL: [1] (422) kill error: No such process
stress: FAIL: [1] (452) failed run completed in 0s
stress: info: [1] dispatching hogs: 0 cpu, 0 io, 1 vm, 0 hdd
stress: dbug: [1] using backoff sleep of 3000us
stress: dbug: [1] --> hogvm worker 1 [8] forked
```

因为容器需要200M，超出了最大限制100Mi，所以容器无法运行。

- 如果容器超过其内存限制，则会被终止。如果可重新启动，则与其他所有类型的运行故障一样，kubelet将重新启动它。
- 如果一个容器超过其内存要求，那么当节点内存不足时，它的pod可能被逐出。

当资源限制没冲突的时候正常启动

```yaml
cat<< EOF >limit-memory-pod.yaml
apiVersion: apps/v1
kind: Deployment
metadata:  
  name: memory-demo
spec:  
  replicas: 1
  selector:    
    matchLabels:      
      app: memory-demo  
  template:    
    metadata:      
      labels:        
        app: memory-demo    
    spec:      
      containers:      
      - name: memory-demo        
        image: progrium/stress:latest
        args:
        - --vm
        - "1"
        - --vm-bytes
        - 200M           #容器使用200M
        resources:
          requests:      #资源需求，下限 
            memory: 50Mi
          limits:        #资源限制，上限
            memory: 300Mi    #将最大限制改为300mi，容器可以正常运行
EOF
kubectl apply -f limit-memory-pod.yaml
```

查看状态

```bash
[root@supper ~]# kubectl get pod
NAME                          READY   STATUS             RESTARTS   AGE
memory-demo-8df545dc9-27tjj   1/1     Running                0      2m44s
```

查看日志

```yaml
[root@supper ~]# kubectl logs memory-demo-8df545dc9-fsg57
stress: dbug: [8] allocating 209715200 bytes ...
stress: dbug: [8] touching bytes in strides of 4096 bytes ...
stress: dbug: [8] freed 209715200 bytes
stress: dbug: [8] allocating 209715200 bytes ...
stress: dbug: [8] touching bytes in strides of 4096 bytes ...
stress: dbug: [8] freed 209715200 bytes
stress: dbug: [8] allocating 209715200 bytes ...
stress: dbug: [8] touching bytes in strides of 4096 bytes ...
stress: dbug: [8] freed 209715200 bytes
stress: dbug: [8] allocating 209715200 bytes ...
....
```

资源限制内部机制使用的是cgroup类型
目录： /sys/fs/cgroup/systemd

## 3、cpu资源限制

```yaml
cat<< EOF >limit-cpu-pod.yaml
apiVersion: apps/v1
kind: Deployment
metadata:  
  name: cpu-demo
spec:  
  replicas: 1
  selector:    
    matchLabels:      
      app: cpu-demo  
  template:    
    metadata:      
      labels:        
        app: cpu-demo    
    spec:      
      containers:      
      - name: cpu-demo        
        image: progrium/stress:latest
        args:
        - -c
        - "2"
        resources:
          requests:      #资源需求，下限 
            cpu: 5
          limits:        #资源限制，上限
            cpu: 10 
EOF
kubectl apply -f limit-cpu-pod.yaml
```

查看状态

```bash
[root@supper ~]# kubectl get pod
NAME                        READY   STATUS    RESTARTS   AGE
cpu-demo-6f6dc64c56-wh28p   0/1     Pending   0          2m15s
```

调度失败是因为申请的CPU资源超出集群节点所能提供的资源
但CPU 使用率过高，不会被杀死
满足要求

```yaml
cat<< EOF >limit-cpu-pod.yaml
apiVersion: apps/v1
kind: Deployment
metadata:  
  name: cpu-demo
spec:  
  replicas: 1
  selector:    
    matchLabels:      
      app: cpu-demo  
  template:    
    metadata:      
      labels:        
        app: cpu-demo    
    spec:      
      containers:      
      - name: cpu-demo        
        image: progrium/stress:latest
        args:
        - -c
        - "2"
        resources:
          requests:      #资源需求，下限 
            cpu: 1
          limits:        #资源限制，上限
            cpu: 2
EOF
kubectl apply -f limit-cpu-pod.yaml
```

查看状态

```bash
[root@supper ~]# kubectl get pod
NAME                        READY   STATUS    RESTARTS   AGE
cpu-demo-558bff8467-b7gqp   1/1     Running   0          68s
```

## 4、namespace设置资源限制

LimitRange资源限制：

```yaml
cat<< EOF >limit-ns-pod.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: limitrange-memory
spec:
  limits:
  - default:             #默认使用0.5个cpu，512mi内存
      cpu: 0.5
      memory: 512Mi
    defaultRequest:     #默认要求0.1个cpu和256mi内存
      cpu: 0.1
      memory: 256Mi
    max:                #最大2个cpu和1gi内存
      cpu: 1
      memory: 1Gi
    min:                #最小0.1个cpu和100mi内存
      cpu: 0.1
      memory: 100Mi
    type: Container
EOF
kubectl apply -f limit-ns-pod.yaml
```

查看limitranges

```bash
[root@supper ~]# kubectl describe limitranges
Name:       limitrange-memory
Namespace:  default
Type        Resource  Min    Max  Default Request  Default Limit  Max Limit/Request Ratio
----        --------  ---    ---  ---------------  -------------  -----------------------
Container   memory    100Mi  1Gi  256Mi            512Mi          -
Container   cpu       100m   1    100m             500m           -
```

注意：LimitRange 在 namespace 中施加的最小和最大内存限制只有在创建和更新 Pod 时才会被应用。改变 LimitRange 不会对之前创建的 Pod 造成影响。

LimitRange - default xx会自动对没有设置资源限制的pod自动添加限制

ResourceQuota设置配额限制

```yaml
cat<< EOF >limit-quota.yaml 
apiVersion: v1
kind: ResourceQuota
metadata:
  name: mem-cpu-demo
spec:
  hard:
    requests.cpu: 1       #要求cpu1个     即cpu要求不得超过1个cpu
    requests.memory: 1Gi  #要求内存1gi    即内存要求不得超过1Gi
    limits.cpu: 2         #cpu限制2个     即cpu限制不得超过2个cpu
    limits.memory: 2Gi    #内存限制2gi    即内存限制不得超过2Gi
EOF
kubectl apply -f limit-quota.yaml 
```

查看resourcequotas

```bash
[root@supper ~]# kubectl get resourcequotas
NAME           AGE   REQUEST                                     LIMIT
mem-cpu-demo   39s   requests.cpu: 0/1, requests.memory: 0/1Gi   limits.cpu: 0/2, limits.memory: 0/2Gi
[root@supper ~]# kubectl describe resourcequotas
Name:            mem-cpu-demo
Namespace:       default
Resource         Used  Hard
--------         ----  ----
limits.cpu       0     2
limits.memory    0     2Gi
requests.cpu     0     1
requests.memory  0     1Gi
```

一旦设置配额后，后续的容器必须设置请求（4种请求都设置），当然，这只是在rq设置的defult的namespace中，4种请求：每个容器必须设置内存请求（memory request）、内存限额（memory limit）、cpu请求（cpu request）和cpu限额（cpu limit）

资源会统计总的namespace中的资源加以限定，不管是之前创建还是准备创建，创建的ResourceQuota对象将在default名字空间中添加以下限制：

- 每个容器必须设置内存请求（memory request），内存限额（memory limit），cpu请求（cpu
  request）和cpu限额（cpu limit）。
- 所有容器的内存请求总额不得超过1 GiB。
- 所有容器的内存限额总额不得超过2 GiB。
- 所有容器的CPU请求总额不得超过1 CPU。
- 所有容器的CPU限额总额不得超过2 CPU。

## 5、namespace中pod的配额

设置Pod配额以限制可以在namespace中运行的Pod数量

```bash
kubectl create ns test
cat<< EOF >limit-podquata.yaml 
apiVersion: v1
kind: ResourceQuota
metadata:
  name: pod-demo
  namespace: test
spec:
  hard:
    pods: 2    #2个pod
EOF
kubectl apply -f limit-podquata.yaml
```

查看ResourceQuota

```bash
[root@supper ~]# kubectl get ResourceQuota -n test
NAME       AGE   REQUEST     LIMIT
pod-demo   58s   pods: 0/2
[root@supper ~]# kubectl -n test describe resourcequotas pod-demo
Name:       pod-demo
Namespace:  test
Resource    Used  Hard
--------    ----  ----
pods        0     2
```

创建1个pod

```yaml
cat<< EOF >limit-pod.yaml
apiVersion: apps/v1
kind: Deployment
metadata:  
  name: pod-demo
  namespace: test
spec:  
  replicas: 2
  selector:    
    matchLabels:      
      app: pod-demo  
  template:    
    metadata:      
      labels:        
        app: pod-demo    
    spec:      
      containers:      
      - name: limit-pod        
        image: nginx:latest
EOF
kubectl apply -f limit-pod.yaml
```

查看ResourceQuota

```bash
[root@supper ~]# kubectl -n test describe resourcequotas pod-demo
Name:       pod-demo
Namespace:  test
Resource    Used  Hard
--------    ----  ----
pods        2     2
```

再增加2个pod

```yaml
cat<< EOF >limit-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:  
  name: pod-demo-test
  namespace: test  
  labels:    
    app: pod-demo-test
spec:  
  containers:  
  - name: pod-demo-test    
    image: nginx:latest
EOF
```

创建pod

```bash
[root@supper ~]# kubectl apply -f limit-test-pod.yaml
Error from server (Forbidden): error when creating "limit-test-pod.yaml": pods "pod-demo-test" is forbidden: exceeded quota: pod-demo, requested: pods=1, used: pods=2, limited: pods=2
```

再创建一个pod时，会发生错误，因为在当前的namespace中限制两个pod

