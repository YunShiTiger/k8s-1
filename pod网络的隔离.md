## 隔离pod的网络

## 介绍

所谓得隔离Pod网络就是通过限制 pod 可以与其他哪些 pod 通信，通讯分为入站与出站两个方向来确保 pod 之间的网络安全。是否可以进行这些配置取决于集群中使用的容器网络插件。如果网络插件支持，可以通过 NetworkPolicy 资源配置网络隔离。

## NetworkPolicy

一个 NetworkPolicy 会应用在匹配它的标签选择器的 pod 上，指明这些允许访问这些 pod 的源地址，或者这些pod 可以访问的目标地址。这些分别由入向（ ingress) 和出向（ egress ）规则指定。这两种规则都可以匹配由标签选择器选出的 pod ，或者一个 namespac 中的所有 pod ，或者通过无类别域间路由（Classless Inter-Domain Routing, CIDR ）指定的 IP 地址段。 
注意： 

- 入向规则与 负载均衡中的 Ingress 资源无关。
- networkpolicy 也是命名空间层面的资源，所有关联pod 的时候必须指定在pod 所在的命名空间创建，如果不与Pod在同一个命名空间就不会关联成功。

## 在一个命名空间中启用网络隔离

默认情况下，某一命名空间中的pod可以被任意来源访问，如果想阻止客户端访问pod，NetworkPolicy的定义如下

```yaml
cat << EOF >default-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: 
    matchLabels: {}        #空的标签选择器匹配命名空间中的所有pod
EOF
```


创建该NetworkPolicy后，任意客户端都不能访问该命名空间中的pod

## 允许同一命名空间中的部分pod访问一个服务端pod

```yaml
cat << EOF >ns-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-netpolicy
spec:
  podSelector:
    matchLabels:
      app: database     #这个策略确保了对具有app=database标签的pod的访问安全性
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: webserver    #他只允许来自具有app=webserver标签的pod的访问
    ports:
    - port: 5432     #只允许对这个端口的访问
EOF
```

networkpolicy允许具有app=webserver标签的pod访问具有app=database标签的pod，并且仅限访问5432端口，客户端pod通过service访问服务端pod时，NetworkPolicy依然会被执行

## 在不同的kubernetes命名空间之间进行网络隔离

加入有多个租户使用同一kubernetes集群，每个租户有多个命名空间，每个命名空间中有一个标签指明他们属于哪个租户，例如，有一个租户Manning，他的所有命名空间中都有标签tenant:manning，其中 一个命名空间中运行了一个微服务Shopping cart，他需要允许同一租户下的所有命名空间的所有pod访问，其他租户禁止访问，则可以创建如下NetworkPolicy

```yaml
cat << EOF >dfns-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: shoppingcart-netpolicy
spec:
  podSelector:
    matchLabels:
      app: shopping-cart 
  ingress:
  - from:
    - namespaceSelector:     #注意此处
        matchLabels:
          tenant: manning    #只有具有tenant=manning标签的命名空间中运行的pod才可以访问.....
    ports:
    - port: 80
EOF
```

在多租户的kubernetes集群中，租户不能为他们的命名空间添加标签或注释，否则，他们可以规避基于namespaceSelector的入向规则

## 使用CIDR隔离网络

CIDR表示法可以指定一个IP段，例如，为了允许IP在192.168.1.1到192.168.1.255范围内的客户端访问上面提到的微服务，可以建立如下NetworkPolicy或者在上面的NetworkPolicy中添加入向规则

```yaml
cat << EOF >cidr-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ipblock-netpolicy
spec:
  podSelector:
    matchLabels:
      app: shopping-cart
  ingress:
  - from:
    - ipBlock:
        cidr: 192.168.1.0/24
EOF
```

限制pod的对外访问流量

```yaml
cat << EOF >out-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: egress-net-policy
spec:
  podSelector:
    matchLabels:
      app: webserver
  egress:       #限制pod的出网流量
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - port: 5432
EOF
```

即：仅允许具有标签app=webserver的pod访问具有标签app=database的pod，除此之外不能访问任何地址(无论其他pod，还是其他IP，无论集群内还是集群外)