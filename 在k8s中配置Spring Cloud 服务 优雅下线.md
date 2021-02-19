# 在k8s中配置Spring Cloud服务优雅下线

修改 `application.yml` 暴露接口

```yaml
management:
  security:
    enabled: false
  endpoints:
    web:
      exposure:
        include: "*"
```

client 强制下线接口:

```json
curl -X "POST" "http://127.0.0.1:8888/actuator/service-registry?status=DOWN" -H "Content-Type: application/vnd.spring-boot.actuator.v2+json;charset=UTF-8"
```

Eureka Server 强制下线接口：

```json
PUT /eureka/apps/${appId}/${ip:port}/status?value=OUT_OF_SERVICE
```

配置 preStop

```yaml
lifecycle:
  preStop:
    exec:
      command:
        - bash
        - -c                
        - 'curl -X "POST" "http://127.0.0.1:8888/actuator/service-registry?status=DOWN" -H "Content-Type: application/vnd.spring-boot.actuator.v2+json;charset=UTF-8";sleep 90'
```

同时指定一下优雅终止宽限期

```
terminationGracePeriodSeconds: 90
```

完整 demo:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {PROJECT}
  namespace: {K8S_NAMESPACE}
  labels:
    app: {PROJECT}
spec:
  replicas: {REPLICAS}
  selector:
    matchLabels:
      app: {PROJECT}
  template:
    metadata:
      labels:
        app: {PROJECT}
    spec:
      imagePullSecrets:
        - name: harbor-registry
      terminationGracePeriodSeconds: 90
      volumes:
      - name: heap-dumps
        emptyDir: {}
      containers:
      - name: {PROJECT}
        image: {IMAGE_URL}
        imagePullPolicy: Always
        volumeMounts:
        - name: heap-dumps
          mountPath: /dumps
        command: ["java"]
        args: {ARGS}
        ports:
        - containerPort: 8888
        env:
        - name: ENV
          value: {ENV}
        lifecycle:
          preStop:
            exec:
              command:
                - bash
                - -c                
                - 'curl -X POST --data DOWN http://127.0.0.1:8888/service-registry/instance-status -H "Content-Type: application/vnd.spring-boot.actuator.v2+json;charset=UTF-8";sleep 90'
           
      #  resources:
      #    requests:
      #      memory: "1Gi"
      #      cpu: "500m"
      #    limits:
      #      memory: "1200Mi"
      #      cpu: "500m"
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8888
            scheme: HTTP
          initialDelaySeconds: 10
          timeoutSeconds: 2
          periodSeconds: 10     
---      
apiVersion: v1
kind: Service
metadata:
  name: {PROJECT}
  namespace: {K8S_NAMESPACE}
spec:
  type: NodePort
  ports:
  - port: 8888
    protocol: TCP
    targetPort: 8888
  selector:
    app: {PROJECT}
---
apiVersion: extensions/v1beta1
kind: Ingress 
metadata:
  name: {ENV}-{PROJECT}
  namespace: {K8S_NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - host: {ENV}-{PROJECT}.intramirror.cn
    http:
      paths:
      - backend:
          serviceName: {PROJECT}
          servicePort: 8888
        path: /
        pathType: ImplementationSpecific
```

【参考链接】
实用技巧：Spring Cloud 中，如何优雅下线微服务？
[http://www.itmuch.com/spring-cloud-sum/how-to-unregister-service-in-eureka/](http://www.itmuch.com/spring-cloud-sum/how-to-unregister-service-in-eureka/?utm_source=ld246.com)

Spring Cloud 服务优雅下线
[https://www.jianshu.com/p/1e628a74ac90](https://www.jianshu.com/p/1e628a74ac90?utm_source=ld246.com)

在 k8s 中使用 eureka 的几种姿势
[https://gitee.com/sunshanpeng/blog/blob/master/在k8s中使用eureka的几种姿势.md?utm_source=ld246.com](https://gitee.com/sunshanpeng/blog/blob/master/在k8s中使用eureka的几种姿势.md?utm_source=ld246.com)

Kubernetes Pod Hook
[https://i4t.com/4424.html](https://i4t.com/4424.html?utm_source=ld246.com)

使用 k8s 部署 SpringCloud 解决三大问题
[https://www.cnblogs.com/sanduzxcvbnm/p/13212718.html](https://www.cnblogs.com/sanduzxcvbnm/p/13212718.html?utm_source=ld246.com)

Eureka 客户端下线的几种方式比较
[https://blog.csdn.net/CSDN_WYL2016/article/details/107336260](https://blog.csdn.net/CSDN_WYL2016/article/details/107336260?utm_source=ld246.com)
[https://www.cnblogs.com/sanduzxcvbnm/category/1580444.html](https://www.cnblogs.com/sanduzxcvbnm/category/1580444.html?utm_source=ld246.com)
[https://github.com/hellorocky/blog](https://github.com/hellorocky/blog?utm_source=ld246.com)
[https://horus-k.github.io/](https://horus-k.github.io/?utm_source=ld246.com)