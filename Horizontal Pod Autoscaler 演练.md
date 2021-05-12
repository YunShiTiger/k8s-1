# Horizontal Pod Autoscaler 演练

HPA（Horizontal Pod Autoscaler）是kubernetes（以下简称k8s）的一种资源对象，能够根据某些指标对在statefulSet、replicaController、replicaSet等集合中的pod数量进行动态伸缩，使运行在上面的服务对指标的变化有一定的自适应能力。

HPA目前支持四种类型的指标，分别是Resource、Object、External、Pods。其中在稳定版本autoscaling/v1中只支持对CPU指标的动态伸缩，在测试版本autoscaling/v2beta2中支持memory和自定义指标的动态伸缩，并以annotation的方式工作在autoscaling/v1版本中。

## 准备开始

本文示例需要一个运行中的 Kubernetes 集群以及 kubectl，版本为 1.2 或更高。 [Metrics 服务器](https://github.com/kubernetes-incubator/metrics-server/) 需要被部署到集群中，以便通过 [Metrics API](https://github.com/kubernetes/metrics) 提供度量数据。 Horizontal Pod Autoscaler 根据此 API 来获取度量数据。 要了解如何部署 metrics-server，请参考 [metrics-server 文档](https://github.com/kubernetes-incubator/metrics-server/) 。

如果需要为 Horizontal Pod Autoscaler 指定多种资源度量指标，你的 Kubernetes 集群以及 kubectl 至少需要达到 1.6 版本。 此外，如果要使用自定义度量指标，你的 Kubernetes 集群还必须能够与提供这些自定义指标 的 API 服务器通信。 最后，如果要使用与 Kubernetes 对象无关的度量指标，则 Kubernetes 集群版本至少需要 达到 1.10 版本，同样，需要保证集群能够与提供这些外部指标的 API 服务器通信。 更多详细信息，请参阅 [Horizontal Pod Autoscaler 用户指南](https://kubernetes.io/zh/docs/tasks/run-application/horizontal-pod-autoscale/#support-for-custom-metrics)。

## 运行 php-apache 服务器并暴露服务

为了演示 Horizontal Pod Autoscaler，我们将使用一个基于 php-apache 镜像的定制Docker 镜像。Dockerfile 内容如下：

```dockerfile
cat << EOF >Dockerfile
FROM php:5-apache
COPY index.php /var/www/html/index.php
RUN chmod a+rx index.php
EOF
```

该文件定义了一个 index.php 页面来执行一些 CPU 密集型计算：

```php
cat << 'EOF' >index.php
<?php
  $x = 0.0001;
  for ($i = 0; $i <= 1000000; $i++) {
    $x += sqrt($x);
  }
  echo "OK!";
?>
EOF
```

制作镜像

```
docker build -t harbor.wzxmt.com/infra/php-apache:latest .
docker push harbor.wzxmt.com/infra/php-apache:latest
```

创建docker-registry

```
kubectl create secret docker-registry harborlogin \
--namespace=default  \
--docker-server=https://harbor.wzxmt.com \
--docker-username=admin \
--docker-password=admin
```

首先，我们使用下面的配置启动一个 Deployment 来运行这个镜像并暴露一个服务：

```yaml
cat << EOF >php-apache.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
spec:
  selector:
    matchLabels:
      run: php-apache
  replicas: 1
  template:
    metadata:
      labels:
        run: php-apache
    spec:
      imagePullSecrets:
      - name: harborlogin
      containers:
      - name: php-apache
        image: harbor.wzxmt.com/infra/php-apache:latest
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: 500m
          requests:
            cpu: 200m
---
apiVersion: v1
kind: Service
metadata:
  name: php-apache
  labels:
    run: php-apache
spec:
  ports:
  - port: 80
  selector:
    run: php-apache
EOF
```

运行下面的命令：

```shell
kubectl apply -f php-apache.yaml
```

## 创建 Horizontal Pod Autoscaler

现在，php-apache 服务器已经运行，我们将通过 kubectl autoscale命令创建 Horizontal Pod Autoscaler。 以下命令将创建一个 Horizontal Pod Autoscaler 用于控制我们上一步骤中创建的 Deployment，使 Pod 的副本数量维持在 1 到 10 之间。 大致来说，HPA 将（通过 Deployment）增加或者减少 Pod 副本的数量以保持所有 Pod 的平均 CPU 利用率在 50% 左右（由于每个 Pod 请求 200 毫核的 CPU，这意味着平均 CPU 用量为 100 毫核）。 

```shell
kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=10
```

我们可以通过以下命令查看 Autoscaler 的状态：

```shell
kubectl get hpa
NAME         REFERENCE                     TARGET    MINPODS   MAXPODS   REPLICAS   AGE
php-apache   Deployment/php-apache/scale   0% / 50%  1         10        1          18s
```

请注意当前的 CPU 利用率是 0%，这是由于我们尚未发送任何请求到服务器 （CURRENT 列显示了相应 Deployment 所控制的所有 Pod 的平均 CPU 利用率）。

## 以声明式方式创建 Autoscaler

```yaml
cat << EOF >hpa-php-apache.yaml
apiVersion: autoscaling/v1
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
EOF
```

使用如下命令创建 autoscaler：

```shell
kubectl apply -f hpa-php-apache.yaml
```

## 增加负载

现在，我们将看到 Autoscaler 如何对增加负载作出反应。 我们将启动一个容器，并通过一个循环向 php-apache 服务器发送无限的查询请求 （请在另一个终端中运行以下命令）：

```shell
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"
```

一分钟时间左右之后，通过以下命令，我们可以看到 CPU 负载升高了：

```shell
kubectl get hpa
NAME         REFERENCE                     TARGET      MINPODS   MAXPODS   REPLICAS   AGE
php-apache   Deployment/php-apache/scale   305% / 50%  1         10        1          3m
```

这时，由于请求增多，CPU 利用率已经升至请求值的 305%。 可以看到，Deployment 的副本数量已经增长到了 7：

```shell
kubectl get deployment php-apache
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
php-apache   7/7      7           7           19m
```

> **说明：** 有时最终副本的数量可能需要几分钟才能稳定下来。由于环境的差异， 不同环境中最终的副本数量可能与本示例中的数量不同。

## 停止负载

我们将通过停止负载来结束我们的示例。

在我们创建 busybox 容器的终端中，输入`<Ctrl> + C` 来终止负载的产生。

然后我们可以再次检查负载状态（等待几分钟时间）：

```shell
kubectl get hpa
NAME         REFERENCE                     TARGET       MINPODS   MAXPODS   REPLICAS   AGE
php-apache   Deployment/php-apache/scale   0% / 50%     1         10        1          11m
kubectl get deployment php-apache
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
php-apache   1/1     1            1           27m
```

这时，CPU 利用率已经降到 0，所以 HPA 将自动缩减副本数量至 1。

> **说明：** 自动扩缩完成副本数量的改变可能需要几分钟的时间。

### 基于多项度量指标和自定义度量指标自动扩缩

```yaml
cat << EOF >hpa-resource-apache.yaml
apiVersion: autoscaling/v2beta2
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
status:
  observedGeneration: 1
  lastScaleTime: <some-time>
  currentReplicas: 1
  desiredReplicas: 1
  currentMetrics:
  - type: Resource
    resource:
      name: cpu
      current:
        averageUtilization: 0
        averageValue: 0
EOF
```

需要注意的是，`targetCPUUtilizationPercentage` 字段已经被名为 `metrics` 的数组所取代。 CPU 利用率这个度量指标是一个 *resource metric*（资源度量指标），因为它表示容器上指定资源的百分比。 除 CPU 外，你还可以指定其他资源度量指标。默认情况下，目前唯一支持的其他资源度量指标为内存。 只要 `metrics.k8s.io` API 存在，这些资源度量指标就是可用的，并且他们不会在不同的 Kubernetes 集群中改变名称。

你还可以指定资源度量指标使用绝对数值，而不是百分比，你需要将 `target.type` 从 `Utilization` 替换成 `AverageValue`，同时设置 `target.averageValue` 而非 `target.averageUtilization` 的值。

还有两种其他类型的度量指标，他们被认为是 *custom metrics*（自定义度量指标）： 即 Pod 度量指标和 Object 度量指标。 这些度量指标可能具有特定于集群的名称，并且需要更高级的集群监控设置。

第一种可选的度量指标类型是 Pod 度量指标。这些指标从某一方面描述了 Pod， 在不同 Pod 之间进行平均，并通过与一个目标值比对来确定副本的数量。 它们的工作方式与资源度量指标非常相像，只是它们仅支持 `target` 类型为 `AverageValue`。

pod 度量指标通过如下代码块定义：

```yaml
type: Pods
pods:
  metric:
    name: packets-per-second
  target:
    type: AverageValue
    averageValue: 1k
```

第二种可选的度量指标类型是对象（Object）度量指标。这些度量指标用于描述 在相同名字空间中的别的对象，而非 Pods。 请注意这些度量指标不一定来自某对象，它们仅用于描述这些对象。 对象度量指标支持的 `target` 类型包括 `Value` 和 `AverageValue`。 如果是 `Value` 类型，`target` 值将直接与 API 返回的度量指标比较， 而对于 `AverageValue` 类型，API 返回的度量值将按照 Pod 数量拆分， 然后再与 `target` 值比较。 下面的 YAML 文件展示了一个表示 `requests-per-second` 的度量指标。

```yaml
type: Object
object:
  metric:
    name: requests-per-second
  describedObject:
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    name: main-route
  target:
    type: Value
    value: 2k
```

如果你指定了多个上述类型的度量指标，HorizontalPodAutoscaler 将会依次考量各个指标。 HorizontalPodAutoscaler 将会计算每一个指标所提议的副本数量，然后最终选择一个最高值。

比如，如果你的监控系统能够提供网络流量数据，你可以通过 `kubectl edit` 命令 将上述 Horizontal Pod Autoscaler 的定义更改为：

```yaml
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: AverageUtilization
        averageUtilization: 50
  - type: Pods
    pods:
      metric:
        name: packets-per-second
      target:
        type: AverageValue
        averageValue: 1k
  - type: Object
    object:
      metric:
        name: requests-per-second
      describedObject:
        apiVersion: networking.k8s.io/v1beta1
        kind: Ingress
        name: main-route
      target:
        kind: Value
        value: 10k
status:
  observedGeneration: 1
  lastScaleTime: <some-time>
  currentReplicas: 1
  desiredReplicas: 1
  currentMetrics:
  - type: Resource
    resource:
      name: cpu
    current:
      averageUtilization: 0
      averageValue: 0
  - type: Object
    object:
      metric:
        name: requests-per-second
      describedObject:
        apiVersion: networking.k8s.io/v1beta1
        kind: Ingress
        name: main-route
      current:
        value: 10k
```

这样，你的 HorizontalPodAutoscaler 将会尝试确保每个 Pod 的 CPU 利用率在 50% 以内， 每秒能够服务 1000 个数据包请求， 并确保所有在 Ingress 后的 Pod 每秒能够服务的请求总数达到 10000 个。

### 基于更特别的度量值来扩缩

许多度量流水线允许你通过名称或附加的 *标签* 来描述度量指标。 对于所有非资源类型度量指标（Pod、Object 和后面将介绍的 External）， 可以额外指定一个标签选择算符。例如，如果你希望收集包含 `verb` 标签的 `http_requests` 度量指标，可以按如下所示设置度量指标块，使得扩缩操作仅针对 GET 请求执行：

```yaml
type: Object
object:
  metric:
    name: http_requests
    selector: verb=GET
```

这个选择算符使用与 Kubernetes 标签选择算符相同的语法。 如果名称和标签选择算符匹配到多个系列，监测管道会决定如何将多个系列合并成单个值。 选择算符是可以累加的，它不会选择目标以外的对象（类型为 `Pods` 的目标 Pods 或者 类型为 `Object` 的目标对象）。

### 基于与 Kubernetes 对象无关的度量指标执行扩缩

运行在 Kubernetes 上的应用程序可能需要基于与 Kubernetes 集群中的任何对象 没有明显关系的度量指标进行自动扩缩， 例如那些描述与任何 Kubernetes 名字空间中的服务都无直接关联的度量指标。 在 Kubernetes 1.10 及之后版本中，你可以使用外部度量指标（external metrics）。

使用外部度量指标时，需要了解你所使用的监控系统，相关的设置与使用自定义指标时类似。 外部度量指标使得你可以使用你的监控系统的任何指标来自动扩缩你的集群。 你只需要在 `metric` 块中提供 `name` 和 `selector`，同时将类型由 `Object` 改为 `External`。 如果 `metricSelector` 匹配到多个度量指标，HorizontalPodAutoscaler 将会把它们加和。 外部度量指标同时支持 `Value` 和 `AverageValue` 类型，这与 `Object` 类型的度量指标相同。

例如，如果你的应用程序处理来自主机上消息队列的任务， 为了让每 30 个任务有 1 个工作者实例，你可以将下面的内容添加到 HorizontalPodAutoscaler 的配置中。

```yaml
- type: External
  external:
    metric:
      name: queue_messages_ready
      selector: "queue=worker_tasks"
    target:
      type: AverageValue
      averageValue: 30
```

如果可能，还是推荐定制度量指标而不是外部度量指标，因为这便于让系统管理员加固定制度量指标 API。 而外部度量指标 API 可以允许访问所有的度量指标。 当暴露这些服务时，系统管理员需要仔细考虑这个问题。

