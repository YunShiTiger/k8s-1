## 生成启动需要密码的ssl证书

生成证书和密钥

 -des3: CBC模式的DES加密

```bash
mkdir -p ssl && cd ssl
openssl genrsa -des3 -out server.key 1024
```

输入密码2次

```bash
Generating RSA private key, 1024 bit long modulus
...............................................................++++++
.......................................++++++
e is 65537 (0x10001)
Enter pass phrase for server.key:
Verifying - Enter pass phrase for server.key:
```

创建服务器证书的申请文件

```bash
openssl req -new -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=*.wzxmt.com" -key server.key -out server.csr
```

输入上面的密码

```bash
Enter pass phrase for server.key:
```

### 生成需要验证的证书

```bash
openssl x509 -req -days 180 -in server.csr -signkey server.key -out server.crt
```

在输入一次密码

```bash
Signature ok
subject=/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=*.wzxmt.com
Getting Private key
Enter pass phrase for server.key:
```

经验证，配置ssl证书后，nginx重载需要输入密码

### 生成需不需验证的证书

备份文件，跳过证书验证密码

```bash
cp server.key server.key.org
openssl rsa -in server.key.org -out server.key
```

在输入一次密码

```bash
Enter pass phrase for server.key.org:
writing RSA key
```

生成证书， 证书有效天数(如果输入9999表示永久) 签名，开启双向认证

```bash
openssl x509 -req -days 180 -in server.csr -signkey server.key -out server.crt
```