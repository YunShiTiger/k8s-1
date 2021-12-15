## 简介

Trivy 是一个简单而且功能完整的容器漏洞扫描工具，特别使用用于持续集成。

## 特点

- 全面检测漏洞
  - 操作系统 (Alpine, **Red Hat Universal Base Image**, Red Hat Enterprise Linux, CentOS, Debian and Ubuntu)
  - **应用依赖** (Bundler, Composer, Pipenv, npm, yarn and Cargo)
- 简单
  - Specify only an image name
  - 详情请看 [Quick Start](https://github.com/knqyf263/trivy#quick-start) 和 [Examples](https://github.com/knqyf263/trivy#examples)
- 易于安装
  - **No need for prerequirements** such as installation of DB, libraries, etc.
  - `apt-get install `, `yum install ` and `brew install ` is possible (See [Installation](https://github.com/knqyf263/trivy#installation))
- 准确度高
  - **Especially Alpine Linux and RHEL/CentOS** (See [Comparison with other scanners](https://github.com/knqyf263/trivy#comparison-with-other-scanners))
  - Other OSes are also high
- DevSecOps
  - **Suitable for CI** such as Travis CI, CircleCI, Jenkins, etc.
  - See [CI Example](https://github.com/knqyf263/trivy#continuous-integration-ci)

## 安装

```bash
cat << 'EOF' >/etc/yum.repos.d/trivy.repo
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$releasever/$basearch/
gpgcheck=0
enabled=1
EOF
yum -y install trivy
```

## 使用

这个工具的最大闪光点就是提供了很多适合用在自动化场景的用法。

### 扫描镜像：

```
trivy centos
```

### 扫描镜像文件

```
docker save ruby:2.3.0-alpine3.9 -o ruby-2.3.0.tar
trivy --input ruby-2.3.0.tar
```

### 根据严重程度进行过滤

```
trivy --severity HIGH,CRITICAL ruby:2.3.0
```

### 忽略未修复问题

```
trivy --ignore-unfixed ruby:2.3.0
```

### 忽略特定问题

使用 `.trivyignore`：

```
cat .trivyignore
# Accept the risk
CVE-2018-14618

# No impact in our settings
CVE-2019-1543

trivy python:3.4-alpine3.9
```

### 使用 JSON 输出结果

```
trivy -f json dustise/translat-chatbot:20190428-5
```

### 定义返回值

```
trivy --exit-code 0 --severity MEDIUM,HIGH ruby:2.3.0
trivy --exit-code 1 --severity CRITICAL ruby:2.3.0
```

## 总结

相对于其它同类工具，Trivy 非常适合自动化操作，从 CircleCI 之类的公有服务，到企业内部使用的 Jenkins、Gitlab 等私有工具，或者作为开发运维人员的自测环节，都有 Trivy 的用武之地。