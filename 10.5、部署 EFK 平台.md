## 添加 Google incubator 仓库

```bash
helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
```

## 部署 Elasticsearch

```bash
kubectl create namespace efkhelm fetch incubator/elasticsearchhelm  install --name els1 --namespace=efk -f values.yaml incubator/elasticsearchkubectl  run cirror-$RANDOM--rm-it--image=cirros -- /bin/sh
curl Elasticsearch:Port/_cat/nodes
```

## 部署 Fluentd

```bash
helm fetch stable/fluentd-elasticsearch
vim  values.yaml
# 更改其中 Elasticsearch 访问地址
helm install --name flu1 --namespace=efk -f values.yaml stable/fluentd-elasticsearch
```

## 部署 kibana

```bash
helm fetch stable/kibana --version0.14.8
helm install --name kib1 --namespace=efk -f values.yaml stable/kibana --version0.14.8
```

