# 让我们重新谱写这段旋律吧
FROM alpine:latest AS builder

# 安装编译依赖，就像准备一场盛宴的食材
RUN apk add --no-cache \
    gcc g++ make perl curl pcre-dev zlib-dev \
    linux-headers openssl-dev git cmake go

# 克隆boringssl，像采集晨曦中的露水一样小心
WORKDIR /src
RUN git clone https://github.com/google/boringssl.git && \
    cd boringssl && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_POSITION_INDEPENDENT_CODE=on .. && \
    make

# 克隆并构建quiche - 就像寻找风之秘谱
WORKDIR /src
RUN git clone --recursive https://github.com/cloudflare/quiche.git && \
    cd quiche && \
    cargo build --release --features ffi,pkg-config-meta,qlog

# 获取nginx源码
WORKDIR /src
RUN curl -O https://nginx.org/download/nginx-1.26.3.tar.gz && \
    tar -xzf nginx-1.26.3.tar.gz && \
    cd nginx-1.26.3 && \
    patch -p01 < /src/quiche/extras/nginx/nginx-1.26.3.patch

# 构建nginx
WORKDIR /src/nginx-1.26.3
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
    --with-quiche=/src/quiche && \
    make && make install

# 设置运行镜像
FROM alpine:latest
RUN apk add --no-cache pcre openssl ca-certificates
COPY --from=builder /usr/sbin/nginx /usr/sbin/
COPY --from=builder /etc/nginx /etc/nginx
RUN mkdir -p /var/log/nginx /var/cache/nginx

EXPOSE 80 443
CMD ["nginx", "-g", "daemon off;"]
