# Nginx HTTP/3 Docker

这个项目提供了一个支持HTTP/3的Nginx Docker配置。HTTP/3基于QUIC协议，提供更快的连接建立和更好的性能，特别是在不稳定的网络条件下。

## 特性

- Nginx与HTTP/3支持
- 基于Alpine的轻量级Docker镜像
- 包含示例配置
- 使用docker-compose简化部署

## 使用方法

1. 确保安装了Docker和docker-compose
2. 克隆此仓库
   - 运行`echo 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 | docker login ghcr.io -u Mryan2005 --password-stdin`
   - 运行`docker pull ghcr.io/venti-and-xiao/nginx-support-http3-docker-base:latest`
3. 运行 `docker-compose up -d`
5. 访问 https://localhost 测试HTTP/3连接

## 证书设置

项目使用自签名证书进行测试。在生产环境中，建议使用有效的TLS证书。
