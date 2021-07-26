# k8s删除Terminating状态的命名空间

查看ingress-system的namespace描述

```
kubectl get ns ingress-system  -o json > namespace-delete.json
```


编辑json文件，删除spec字段的内存，因为k8s集群时需要认证的。

namespace-delete.json
将

```
"spec": {
        "finalizers": [
            "kubernetes"
        ]
    },
```

更改为：

```
"spec": {
    
  },
```


新开一个窗口运行kubectl proxy跑一个API代理在本地的8081端口

```
kubectl proxy --port=8081
Starting to serve on 127.0.0.1:8081
```


最后运行curl命令进行删除

```
curl -k -H "Content-Type:application/json" -X PUT --data-binary @namespace-delete.json http://127.0.0.1:8081/api/v1/namespaces/ingress-system/finalize
```

