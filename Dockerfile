FROM ubuntu:latest AS builder

# 更新包列表
RUN apt-get update

# 安装构建工具和依赖，就像为一场完美的诗会做准备～
RUN apt-get install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev linux-headers-$(uname -r) git wget 
RUN apt-get install -y \
    gcc \
    g++ \
    make \
    cmake \
    perl \
    linux-headers-$(uname -r) \
    libssl-dev \
    libpcre3-dev \
    zlib1g-dev \
    curl \
    git \
    wget
# 安装Rustup工具，就像风带来的礼物～
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# 配置环境变量
ENV PATH="/root/.cargo/bin:${PATH}"

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
RUN git clone --recursive https://github.com/cloudflare/quiche
WORKDIR /src/quiche
RUN cargo build --examples

# 啊，最关键的风之魔法——应用补丁！
WORKDIR /src/nginx-1.26.3

RUN mv /src/quiche /src/nginx-1.26.3/

RUN wget https://github.com/openssl/openssl/releases/download/openssl-3.0.13/openssl-3.0.13.tar.gz
RUN tar -xzvf openssl-3.0.13.tar.gz
RUN cd openssl-3.0.13
RUN ./config  --prefix=/usr/local/openssl
RUN make
RUN make install


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
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-cc-opt="-I../boringssl/include" \
    --with-ld-opt="-L../boringssl/build/ssl -L../boringssl/build/crypto"
    
RUN make
RUN make install

# 最终镜像，像风一样轻盈～
FROM ubuntu:latest

# 复制构建好的文件，像收集风中的蒲公英种子
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /src/boringssl/build/ssl/libssl.so /usr/lib/
COPY --from=builder /src/boringssl/build/crypto/libcrypto.so /usr/lib/

# 添加运行依赖，像为歌谣添加伴奏
RUN apt-get update && apt-get install -y libpcre3 libssl1.1 zlib1g && \
    mkdir -p /var/log/nginx && \
    mkdir -p /var/cache/nginx

# 添加Nginx用户，像风给树叶安家
RUN addgroup --system nginx && \
    adduser --system --no-create-home --disabled-login --ingroup nginx nginx

# 准备配置和文件，像布置一场音乐会
COPY nginx.conf /etc/nginx/nginx.conf
COPY certs/ /etc/nginx/certs/
COPY html/ /usr/share/nginx/html/

# 打开门窗，让风自由穿行
EXPOSE 80 443/tcp 443/udp

# 启动我们的音乐会！
CMD ["nginx", "-g", "daemon off;"]
