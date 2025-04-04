FROM ubuntu:latest AS builder

# Update package lists
RUN apt-get update

# Install build tools and dependencies
RUN apt-get install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev git wget
RUN apt-get install -y \
    gcc \
    g++ \
    make \
    cmake \
    perl \
    libssl-dev \
    libpcre3-dev \
    zlib1g-dev \
    curl

# Fix: Install clang and libclang properly
RUN apt-get install -y clang libclang-dev

# Install Rustup tool
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Configure environment variables
ENV PATH="/root/.cargo/bin:${PATH}"
# Fix: Set the correct LIBCLANG_PATH
ENV LIBCLANG_PATH=/usr/lib/llvm-10/lib

# Build BoringSSL (needed for HTTP/3)
WORKDIR /src
RUN git clone https://github.com/google/boringssl.git
WORKDIR /src/boringssl
RUN mkdir build
WORKDIR /src/boringssl/build
RUN cmake -DCMAKE_POSITION_INDEPENDENT_CODE=on ..
RUN make -j$(nproc)

# Download and extract Nginx
WORKDIR /src
RUN curl -O https://nginx.org/download/nginx-1.26.3.tar.gz && \
    tar -xzf nginx-1.26.3.tar.gz

# Download and build quiche (QUIC implementation)
WORKDIR /src
RUN git clone --recursive https://github.com/cloudflare/quiche
WORKDIR /src/quiche
# Fix: Explicitly install additional dependencies before building
RUN apt-get install -y llvm-dev libclang-dev
RUN cargo build --examples

# Move quiche to the nginx directory
WORKDIR /src/nginx-1.26.3
RUN mv /src/quiche /src/nginx-1.26.3/

# Install OpenSSL
WORKDIR /src
RUN wget https://github.com/openssl/openssl/releases/download/openssl-3.0.13/openssl-3.0.13.tar.gz
RUN tar -xzvf openssl-3.0.13.tar.gz
WORKDIR /src/openssl-3.0.13
RUN ./config --prefix=/usr/local/openssl
RUN make
RUN make install

WORKDIR /src/nginx-1.26.3

RUN wget https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_0l/openssl-1.1.0l.tar.gz
RUN tar -xzvf openssl-1.1.0l.tar.gz

# Configure Nginx with HTTP/3 support
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
    --with-cc-opt="-I../boringssl/include -I/usr/local/openssl/include" \
    --with-ld-opt="-L../boringssl/build/ssl -L../boringssl/build/crypto -L/usr/local/openssl/lib" \
    --with-openssl=/src/nginx-1.26.3/openssl-1.1.0l

RUN make
RUN make install

# Final image
FROM ubuntu:latest

# Copy built files
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /src/boringssl/build/ssl/libssl.so /usr/lib/
COPY --from=builder /src/boringssl/build/crypto/libcrypto.so /usr/lib/

# Create necessary directories
RUN mkdir -p /var/cache/nginx/client_temp /var/cache/nginx/proxy_temp \
            /var/cache/nginx/fastcgi_temp /var/cache/nginx/uwsgi_temp \
            /var/cache/nginx/scgi_temp

# Add runtime dependencies
RUN apt-get update && apt-get install -y libpcre3 libssl1.1 zlib1g && \
    mkdir -p /var/log/nginx && \
    mkdir -p /var/cache/nginx

# Add Nginx user
RUN addgroup --system nginx && \
    adduser --system --no-create-home --disabled-login --ingroup nginx nginx

# Prepare configuration and files
COPY nginx.conf /etc/nginx/nginx.conf
COPY certs/ /etc/nginx/certs/
COPY html/ /usr/share/nginx/html/

# Expose ports
EXPOSE 80 443/tcp 443/udp

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
