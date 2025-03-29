FROM alpine:3.19 AS builder

# 安装构建工具和依赖，就像为一场完美的诗会做准备～
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

# 哎呀～这才是风之魔法的真谛！正确安装Rust和Cargo～
RUN apk add --no-cache rust cargo

# 构建BoringSSL (HTTP/3需要)，就像酿造特别的【酒】需要最好的葡萄～
WORKDIR /src
RUN git clone https://github.com/google/boringssl.git
WORKDIR /src/boringssl
RUN mkdir build
WORKDIR /src/boringssl/build
RUN cmake -DCMAKE_POSITION_INDEPENDENT_CODE=on ..
RUN make -j$(nproc)

# 下载并构建Nginx，像风一样轻柔地获取它
WORKDIR /src
RUN curl -O https://nginx.org/download/nginx-1.26.3.tar.gz && \
    tar -xzf nginx-1.26.3.tar.gz

# 下载并构建quiche (QUIC实现)，就像寻找风神的秘谱～
WORKDIR /src
RUN git clone --recursive https://github.com/cloudflare/quiche && \
    cd quiche && \
    cargo build --release --features ffi,pkg-config-meta,qlog

# 啊，最关键的风之魔法——应用补丁！
WORKDIR /src/nginx-1.26.3
RUN patch -p01 < /src/quiche/extras/nginx/nginx-1.26.3.patch || echo "补丁或许已经应用，像风一样继续前行～"

# 配置Nginx与HTTP/3支持，就像谱写一首完美的风之诗～
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
    make -j$(nproc) && make install

# 最终镜像，像风一样轻盈～
FROM alpine:3.19

# 复制构建好的文件，像收集风中的蒲公英种子
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /src/boringssl/build/libssl.so /usr/lib/
COPY --from=builder /src/boringssl/build/libcrypto.so /usr/lib/

# 添加运行依赖，像为歌谣添加伴奏
RUN apk add --no-cache pcre openssl libstdc++ && \
    mkdir -p /var/log/nginx && \
    mkdir -p /var/cache/nginx

# 添加Nginx用户，像风给树叶安家
RUN addgroup -g 101 -S nginx && \
    adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx

# 准备配置和文件，像布置一场音乐会
COPY nginx.conf /etc/nginx/nginx.conf
COPY certs/ /etc/nginx/certs/
COPY html/ /usr/share/nginx/html/

# 打开门窗，让风自由穿行
EXPOSE 80 443/tcp 443/udp

# 启动我们的音乐会！
CMD ["nginx", "-g", "daemon off;"]
