FROM alpine:3.19 AS builder

# 安装构建工具和依赖
RUN apk add --no-cache \
    gcc \
    g++ \
    make \
    cmake \
    perl \
    linux-headers \
    openssl-dev \
    pcre-dev \
    zlib-dev \
    curl \
    git

# 构建BoringSSL (HTTP/3需要)
WORKDIR /src
RUN git clone https://github.com/google/boringssl.git
WORKDIR /src/boringssl
RUN mkdir build
WORKDIR /src/boringssl/build
RUN cmake ..
RUN make -j$(nproc)

# 下载并构建Nginx
WORKDIR /src
RUN curl -O https://nginx.org/download/nginx-1.25.3.tar.gz && \
    tar -xzf nginx-1.25.3.tar.gz

# 下载并构建quiche (QUIC实现)
RUN git clone --recursive https://github.com/cloudflare/quiche
WORKDIR /src/nginx-1.25.3

# 配置Nginx与HTTP/3支持
RUN ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-openssl=/src/boringssl \
    --with-quiche=/src/quiche

RUN make -j$(nproc) && make install

# 最终镜像
FROM alpine:3.19

COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /src/boringssl/build/libssl.so /usr/lib/
COPY --from=builder /src/boringssl/build/libcrypto.so /usr/lib/

RUN apk add --no-cache pcre openssl && \
    mkdir -p /var/log/nginx && \
    mkdir -p /var/cache/nginx

# 添加Nginx用户
RUN addgroup -g 101 -S nginx && \
    adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx

COPY nginx.conf /etc/nginx/nginx.conf
COPY certs/ /etc/nginx/certs/
COPY html/ /usr/share/nginx/html/

EXPOSE 80 443/tcp 443/udp

CMD ["nginx", "-g", "daemon off;"]
