## ansible  系统优化
```bash
# ansible 版本 2.8 
# 安装K8S 内核优化，可以增加删除相关配置，里面有修改系统源，请大家根据自己需求修改
# 部署方式  ansible-playbook -i 10.0.0.31, package-sysctl.yml   
# 需要部署的节点IP 多个IP ansible-playbook -i 10.0.0.31,10.0.0.32, package-sysctl.yml 
# 在centos 7,8 Ubuntu 18.04 19.04 进行测试完美运行
```