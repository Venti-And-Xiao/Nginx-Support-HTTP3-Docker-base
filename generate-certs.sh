#!/bin/sh
# 生成自签名证书用于测试

mkdir -p certs
cd certs

# 生成私钥
openssl genrsa -out server.key 2048

# 生成自签名证书
openssl req -new -x509 -key server.key -out server.crt -days 365 -subj "/CN=localhost"

echo "已生成自签名证书。在生产环境中，请使用有效的证书。"
