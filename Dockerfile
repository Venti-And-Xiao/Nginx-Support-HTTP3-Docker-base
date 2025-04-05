FROM ubuntu:22.04 AS builder

# Set non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git wget build-essential libpcre3-dev zlib1g-dev \
    libssl-dev cmake ninja-build golang libunwind-dev \
    pkg-config curl gnupg2 ca-certificates \
    libncurses5-dev libaio-dev bison

# 安装Python 3.11
RUN apt-get update && apt-get install -y \
    software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y python3.11 python3.11-venv python3.11-dev && \
    rm -rf /var/lib/apt/lists/*

# Build BoringSSL (required for QUIC/HTTP3)
WORKDIR /src
RUN git clone https://github.com/google/boringssl.git && \
    cd boringssl && \
    mkdir build && \
    cd build && \
    cmake -GNinja .. && \
    ninja

# Download and build Nginx with HTTP/3
ARG NGINX_VERSION=1.25.4
WORKDIR /src
RUN wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    tar -xzvf nginx-${NGINX_VERSION}.tar.gz && \
    git clone --recursive https://github.com/cloudflare/quiche.git && \
    cd nginx-${NGINX_VERSION} && \
    ./configure \
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
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-cc-opt="-I../quiche/deps/boringssl/include" \
        --with-ld-opt="-L../quiche/deps/boringssl/lib"  && \
    make -j$(nproc) && \
    make install

# Download and install MySQL from .deb bundle
WORKDIR /src
RUN wget https://downloads.mysql.com/archives/get/p/23/file/mysql-server_8.4.3-1ubuntu22.04_amd64.deb-bundle.tar && \
     tar -xvf mysql-server_8.4.3-1ubuntu22.04_amd64.deb-bundle.tar && \
     dpkg -i *.deb || apt-get -f install -y

RUN find / -name 'mysql' -type d

# Create the final image
FROM ubuntu:22.04

LABEL org.opencontainers.image.description DESCRIPTION

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates libpcre3 openssl \
    && rm -rf /var/lib/apt/lists/*

# 安装Python 3.11
RUN apt-get update && \
    apt-get install -y software-properties-common && \
    apt-get install --reinstall ca-certificates  && \
    add-apt-repository --update ppa:ubuntu-toolchain-r/test -y && \
    apt-get update && \
    apt-get install -y python3.11 && \
    rm -rf /var/lib/apt/lists/*

RUN python3 --version

# Copy Nginx and its dependencies from builder
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /var/log/nginx /var/log/nginx
COPY --from=builder /src/boringssl/build/ssl/libssl.a /usr/lib/
COPY --from=builder /src/boringssl/build/crypto/libcrypto.a /usr/lib/

# Copy MySQL binaries from builder
COPY --from=builder /usr/lib/mysql /usr/lib/mysql
COPY --from=builder /etc/mysql /etc/mysql
COPY --from=builder /usr/include/mysql /usr/include/mysql
COPY --from=builder /usr/include/mysql/mysql /usr/include/mysql/mysql

# Create required directories
RUN mkdir -p /var/cache/nginx/client_temp && \
    mkdir -p /etc/nginx/conf.d && \
    mkdir -p /usr/share/nginx/html && \
    mkdir -p /var/lib/mysql && \
    mkdir -p /var/run/mysqld

# Create default configuration with HTTP/3 support
RUN echo 'worker_processes auto;\n\
events {\n\
    worker_connections 1024;\n\
}\n\
\n\
http {\n\
    sendfile on;\n\
    tcp_nopush on;\n\
    tcp_nodelay on;\n\
    keepalive_timeout 65;\n\
    types_hash_max_size 2048;\n\
    include /etc/nginx/mime.types;\n\
    default_type application/octet-stream;\n\
    ssl_protocols TLSv1.3;\n\
    ssl_prefer_server_ciphers on;\n\
    access_log /var/log/nginx/access.log;\n\
    error_log /var/log/nginx/error.log;\n\
    include /etc/nginx/conf.d/*.conf;\n\
}' > /etc/nginx/nginx.conf

# Default site configuration
RUN echo 'server {\
    listen 80;\
    listen 443 ssl http2;\
    listen 443 quic reuseport;\
    server_name localhost;\
    ssl_certificate /etc/nginx/ssl/nginx.crt;\
    ssl_certificate_key /etc/nginx/ssl/nginx.key;\
    ssl_protocols TLSv1.3;\
    add_header Alt-Svc '\''h3=":443"; ma=86400'\'';\
    location / {\
        root /usr/share/nginx/html;\
        index index.html;\
    }\
}' > /etc/nginx/conf.d/default.conf

# Create default index page
RUN echo '<html><body><h1>HTTP/3 Enabled!</h1></body></html>' > /usr/share/nginx/html/index.html

# Forward request logs to Docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Create non-root user
RUN adduser --system --no-create-home --shell /bin/false --group --disabled-login nginx

# Create directory for SSL certificates
RUN mkdir -p /etc/nginx/ssl

# Ensure the mysql user and group exist
RUN groupadd -r mysql && useradd -r -g mysql mysql

# MySQL configuration and initialization
RUN ln -sf /dev/stdout /var/log/mysql/error.log && \
    ln -sf /dev/stdout /var/log/mysql/general.log && \
    chown -R mysql:mysql /var/lib/mysql /var/run/mysqld

# MySQL environment variables
ENV PATH="/usr/local/mysql/bin:${PATH}"
ENV MYSQL_ROOT_PASSWORD=root

# Expose ports
EXPOSE 80 443/tcp 443/udp 3306

STOPSIGNAL SIGQUIT

# Start both MySQL and Nginx
CMD ["/bin/bash", "-c", "mysqld_safe --datadir=/var/lib/mysql & nginx -g 'daemon off;'"]
