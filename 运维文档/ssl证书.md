### 生成证书和密钥

 -des3: CBC模式的DES加密
 -passout: 命令行输入密码

```bash
mkdir -p ssl && cd ssl
openssl genrsa -des3 -passout pass:wzxmt -out server.key 1024
```

创建服务器证书的申请文件

```bash
openssl req -new -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=*.wzxmt.com" -passin pass:wzxmt -key server.key -out server.csr
```

### 生成需要验证的证书

```bash
openssl x509 -req -days 9999 -passin pass:wzxmt -in server.csr -signkey server.key -out server.crt
```

经验证，配置ssl证书后，nginx重载需要输入密码

### 生成需不需验证的证书

备份文件，跳过证书验证密码

```bash
cp server.key server.key.org
openssl rsa -passin pass:wzxmt -in server.key.org -out server.key
```

生成证书， 证书有效天数(如果输入9999表示永久) 签名，开启双向认证

```bash
openssl x509 -req -days 9999 -passin pass:wzxmt -in server.csr -signkey server.key -out server.crt
```

### 转换

**私钥转非加密**

```
openssl rsa -in server.key -passin pass:wzxmt -out rsa_private.key
```

**私钥转加密**

```
openssl rsa -in server.key -aes256 -passout pass:wzxmt -out rsa_aes_private.key
```