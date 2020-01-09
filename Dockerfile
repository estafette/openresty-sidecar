FROM debian:buster-slim

# https://github.com/opentracing/opentracing-cpp/releases/tag/v1.6.0
ARG OPENTRACING_CPP_VERSION="1.5.0"
# https://github.com/opentracing-contrib/nginx-opentracing/releases/tag/v0.9.0
ARG OPENTRACING_NGINX_VERSION="0.9.0"
# https://github.com/jaegertracing/jaeger-client-cpp/releases/tag/v0.5.0
ARG JAEGER_CPP_VERSION="0.5.0"

# https://github.com/openresty/docker-openresty/blob/1.15.8.2-6/bionic/Dockerfile
# Docker Build Arguments
ARG RESTY_VERSION="1.15.8.2"
# ARG RESTY_LUAROCKS_VERSION="3.2.1"
ARG RESTY_OPENSSL_VERSION="1.1.0k"
ARG RESTY_PCRE_VERSION="8.43"
ARG RESTY_J="8"
ARG RESTY_CONFIG_OPTIONS="\
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
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-pcre-jit \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-threads \
    --without-mail_imap_module \
    --without-mail_pop3_module \
    --without-mail_smtp_module \
    "

ARG RESTY_CONFIG_OPTIONS_MORE="--add-dynamic-module=/nginx-opentracing-${OPENTRACING_NGINX_VERSION}/opentracing"
ARG RESTY_LUAJIT_OPTIONS="--with-luajit-xcflags='-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT'"

ARG RESTY_ADD_PACKAGE_BUILDDEPS="cmake dos2unix binutils"
ARG RESTY_ADD_PACKAGE_RUNDEPS="inotify-tools gettext-base libyaml-cpp0.6"
ARG RESTY_EVAL_PRE_CONFIGURE=""
ARG RESTY_EVAL_POST_MAKE=""

# These are not intended to be user-specified
ARG _RESTY_CONFIG_DEPS="--with-pcre \
    --with-cc-opt='-Os -march=x86-64 -DNGX_LUA_ABORT_AT_PANIC -I/usr/local/openresty/zlib/include -I/usr/local/openresty/pcre/include -I/usr/local/openresty/openssl/include' \
    --with-ld-opt='-Wl,-rpath,/usr/local/openresty/luajit/lib -L/usr/local/openresty/zlib/lib -L/usr/local/openresty/pcre/lib -L/usr/local/openresty/openssl/lib -Wl,-rpath,/usr/local/openresty/zlib/lib:/usr/local/openresty/pcre/lib:/usr/local/openresty/openssl/lib' \
    "

RUN set -ex \
    && DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        gettext-base \
        libgd-dev \
        libgeoip-dev \
        libncurses5-dev \
        libperl-dev \
        libreadline-dev \
        libxslt1-dev \
        make \
        perl \
        unzip \
        zlib1g-dev \
        ${RESTY_ADD_PACKAGE_BUILDDEPS} \
        ${RESTY_ADD_PACKAGE_RUNDEPS} \
    # set c optimization flags
    && export CFLAGS="$CFLAGS -Os -march=x86-64" \
    && export CXXFLAGS="$CXXFLAGS -Os -march=x86-64" \
    # build opentracing-cpp
    && curl -fSL https://github.com/opentracing/opentracing-cpp/archive/v${OPENTRACING_CPP_VERSION}.tar.gz | tar xvz -C / \
    && cd /opentracing-cpp-${OPENTRACING_CPP_VERSION} \
    && mkdir build \
    && cd build \
    && cmake -DCMAKE_BUILD_TYPE=Release \
             -DENABLE_LINTING=OFF \
             -DBUILD_MOCKTRACER=OFF \
             -DBUILD_STATIC_LIBS=OFF \
             -DBUILD_TESTING=OFF \
             .. \
    && make -j${RESTY_J} \
    && make -j${RESTY_J} install \
    # build jaeger-client-cpp
    && curl -fSL https://github.com/jaegertracing/jaeger-client-cpp/archive/v${JAEGER_CPP_VERSION}.tar.gz | tar xvz -C / \
    && cd /jaeger-client-cpp-${JAEGER_CPP_VERSION} \
    && mkdir build \
    && cd build \
    && cmake -DCMAKE_BUILD_TYPE=Release \
             -DJAEGERTRACING_BUILD_EXAMPLES=OFF \
             -DBUILD_TESTING=OFF \
             .. \
    && make -j${RESTY_J} \
    && make -j${RESTY_J} install \
    # get nginx-opentracing to build with openresty as dynamic module
    && curl -fSL https://github.com/opentracing-contrib/nginx-opentracing/archive/v${OPENTRACING_NGINX_VERSION}.tar.gz | tar xvz -C / \
    # openresty
    && cd /tmp \
    && if [ -n "${RESTY_EVAL_PRE_CONFIGURE}" ]; then eval $(echo ${RESTY_EVAL_PRE_CONFIGURE}); fi \
    && curl -fSL https://www.openssl.org/source/openssl-${RESTY_OPENSSL_VERSION}.tar.gz -o openssl-${RESTY_OPENSSL_VERSION}.tar.gz \
    && tar xzf openssl-${RESTY_OPENSSL_VERSION}.tar.gz \
    && cd openssl-${RESTY_OPENSSL_VERSION} \
    && if [ $(echo ${RESTY_OPENSSL_VERSION} | cut -c 1-5) = "1.1.1" ] ; then \
        echo 'patching OpenSSL 1.1.1 for OpenResty' \
        && curl -s https://raw.githubusercontent.com/openresty/openresty/master/patches/openssl-1.1.1c-sess_set_get_cb_yield.patch | patch -p1 ; \
    fi \
    && if [ $(echo ${RESTY_OPENSSL_VERSION} | cut -c 1-5) = "1.1.0" ] ; then \
        echo 'patching OpenSSL 1.1.0 for OpenResty' \
        && curl -s https://raw.githubusercontent.com/openresty/openresty/ed328977028c3ec3033bc25873ee360056e247cd/patches/openssl-1.1.0j-parallel_build_fix.patch | patch -p1 \
        && curl -s https://raw.githubusercontent.com/openresty/openresty/master/patches/openssl-1.1.0d-sess_set_get_cb_yield.patch | patch -p1 ; \
    fi \
    && ./config \
      no-threads shared zlib -g \
      enable-ssl3 enable-ssl3-method \
      --prefix=/usr/local/openresty/openssl \
      --libdir=lib \
      -Wl,-rpath,/usr/local/openresty/openssl/lib \
    && make -j${RESTY_J} \
    && make -j${RESTY_J} install_sw \
    && cd /tmp \
    && curl -fSL https://ftp.pcre.org/pub/pcre/pcre-${RESTY_PCRE_VERSION}.tar.gz -o pcre-${RESTY_PCRE_VERSION}.tar.gz \
    && tar xzf pcre-${RESTY_PCRE_VERSION}.tar.gz \
    && cd /tmp/pcre-${RESTY_PCRE_VERSION} \
    && ./configure \
        --prefix=/usr/local/openresty/pcre \
        --disable-cpp \
        --enable-jit \
        --enable-utf \
        --enable-unicode-properties \
    && make -j${RESTY_J} \
    && make -j${RESTY_J} install \
    && cd /tmp \
    && curl -fSL https://github.com/openresty/openresty/releases/download/v${RESTY_VERSION}/openresty-${RESTY_VERSION}.tar.gz -o openresty-${RESTY_VERSION}.tar.gz \
    && tar xzf openresty-${RESTY_VERSION}.tar.gz \
    && cd /tmp/openresty-${RESTY_VERSION} \
    && eval ./configure -j${RESTY_J} ${_RESTY_CONFIG_DEPS} ${RESTY_CONFIG_OPTIONS} ${RESTY_CONFIG_OPTIONS_MORE} ${RESTY_LUAJIT_OPTIONS} \
    && make -j${RESTY_J} \
    && make -j${RESTY_J} install \
    && cd /tmp \
    && rm -rf \
        openssl-${RESTY_OPENSSL_VERSION}.tar.gz openssl-${RESTY_OPENSSL_VERSION} \
        pcre-${RESTY_PCRE_VERSION}.tar.gz pcre-${RESTY_PCRE_VERSION} \
        openresty-${RESTY_VERSION}.tar.gz openresty-${RESTY_VERSION} \
    # && curl -fSL https://luarocks.github.io/luarocks/releases/luarocks-${RESTY_LUAROCKS_VERSION}.tar.gz -o luarocks-${RESTY_LUAROCKS_VERSION}.tar.gz \
    # && tar xzf luarocks-${RESTY_LUAROCKS_VERSION}.tar.gz \
    # && cd luarocks-${RESTY_LUAROCKS_VERSION} \
    # && ./configure \
    #     --prefix=/usr/local/openresty/luajit \
    #     --with-lua=/usr/local/openresty/luajit \
    #     --lua-suffix=jit-2.1.0-beta3 \
    #     --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1 \
    # && make build \
    # && make install \
    # && cd /tmp \
    # strip symbols from binaries
    && { find /usr/lib/ssl -type f -print0 | xargs -0r strip --strip-all -p 2>/dev/null || true; } \
    && { find /usr/lib/x86_64-linux-gnu/engines-1.1 -type f -print0 | xargs -0r strip --strip-all -p 2>/dev/null || true; } \
    && { find /usr/local/lib -type f -print0 | xargs -0r strip --strip-all -p 2>/dev/null || true; } \
    && { find /usr/local/openresty -type f -print0 | xargs -0r strip --strip-all -p 2>/dev/null || true; } \
    && strip --strip-all /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1 \
    && strip --strip-all /usr/lib/x86_64-linux-gnu/libinotifytools.so.0.4.1 \
    && strip --strip-all /usr/lib/x86_64-linux-gnu/libssl.so.1.1 \
    && strip --strip-all /usr/lib/x86_64-linux-gnu/libyaml-cpp.so.0.6.2 \
    && if [ -n "${RESTY_EVAL_POST_MAKE}" ]; then eval $(echo ${RESTY_EVAL_POST_MAKE}); fi \
    # && rm -rf luarocks-${RESTY_LUAROCKS_VERSION} luarocks-${RESTY_LUAROCKS_VERSION}.tar.gz \
    && if [ -n "${RESTY_ADD_PACKAGE_BUILDDEPS}" ]; then DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge ${RESTY_ADD_PACKAGE_BUILDDEPS} ; fi \
    # remove other build dependencies to shrink the final image
    && DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge \
        build-essential \
        # ca-certificates \
        curl \
        # gettext-base \
        libgd-dev \
        libgeoip-dev \
        libncurses5-dev \
        libperl-dev \
        libreadline-dev \
        libxslt1-dev \
        make \
        perl \
        unzip \
        zlib1g-dev \
    && DEBIAN_FRONTEND=noninteractive apt-get autoremove -y \
    && DEBIAN_FRONTEND=noninteractive apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && mkdir -p /var/run/openresty \
    && ln -sf /dev/stdout /usr/local/openresty/nginx/logs/access.log \
    && ln -sf /dev/stderr /usr/local/openresty/nginx/logs/error.log \
    # clean up opentracing source code
    && rm -rf /opentracing-cpp-${OPENTRACING_CPP_VERSION} \
    && rm -rf /nginx-opentracing-${OPENTRACING_NGINX_VERSION} \
    && rm -rf /jaeger-client-cpp-${JAEGER_CPP_VERSION} \
    && rm -rf /root/.hunter \
    && rm -rf /usr/local/lib/cmake \
    && rm -rf /usr/local/lib/libjaegertracing.a \
    && rm -rf /usr/local/openresty/luajit/lib/luajit-5.1.a \
    && rm -rf /usr/local/openresty/openssl/lib/libcrypto.a \
    && rm -rf /usr/local/openresty/openssl/lib/libssl.a \
    && rm -rf /usr/local/openresty/pcre/lib/libpcreposix.a \
    && rm -rf /usr/local/openresty/pcre/lib/libpcre.a \
    && rm -rf /usr/local/openresty/luajit/lib/libluajit-5.1.a \
    # regain wasted space
    && rm -rf /var/cache/debconf \
    && mkdir -p /var/cache/debconf

# Add additional binaries into PATH for convenience
ENV PATH=$PATH:/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin

RUN set -ex \
    && /usr/local/openresty/bin/resty -e 'print(package.path)' \
    && /usr/local/openresty/bin/resty -e 'print(package.cpath)' \
    && /usr/local/openresty/bin/openresty -V

RUN find / -type f -iname "*.a"

# Add LuaRocks paths
# If OpenResty changes, these may need updating:
#    /usr/local/openresty/bin/resty -e 'print(package.path)'
#    /usr/local/openresty/bin/resty -e 'print(package.cpath)'
ENV LUA_PATH="/usr/local/openresty/site/lualib/?.ljbc;/usr/local/openresty/site/lualib/?/init.ljbc;/usr/local/openresty/lualib/?.ljbc;/usr/local/openresty/lualib/?/init.ljbc;/usr/local/openresty/site/lualib/?.lua;/usr/local/openresty/site/lualib/?/init.lua;/usr/local/openresty/lualib/?.lua;/usr/local/openresty/lualib/?/init.lua;./?.lua;/usr/local/openresty/luajit/share/luajit-2.1.0-beta3/?.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;/usr/local/openresty/luajit/share/lua/5.1/?.lua;/usr/local/openresty/luajit/share/lua/5.1/?/init.lua"

ENV LUA_CPATH="/usr/local/openresty/site/lualib/?.so;/usr/local/openresty/lualib/?.so;./?.so;/usr/local/lib/lua/5.1/?.so;/usr/local/openresty/luajit/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/loadall.so"

# sidecar specifics

EXPOSE 80 81 82 443 9101

COPY nginx.vh.default.conf /etc/nginx/conf.d/default.conf
COPY nginx.conf /tmpl/nginx.conf.tmpl
COPY cors.conf /tmpl/cors.conf.tmpl
COPY lua-init.conf /usr/local/openresty/nginx/conf/includes/lua-init.conf
COPY prometheus.lua /tmpl/prometheus.lua.tmpl
COPY jaeger-nginx-config.yaml /tmpl/jaeger-nginx-config.yaml.tmpl
COPY ./docker-entrypoint.sh /

RUN chmod 500 /docker-entrypoint.sh

# embed self-signed certificate for integration testing (at runtime a valid cert is mounted)
COPY ssl/ssl.pem /etc/ssl/private/ssl.pem
COPY ssl/ssl.key /etc/ssl/private/ssl.key

# runtime environment variables
ENV OFFLOAD_TO_HOST=localhost \
    OFFLOAD_TO_PORT=80 \
    OFFLOAD_TO_PROTO=http \
    HEALT_CHECK_PATH=/ \
    ALLOW_CIDRS="allow all;" \
    SERVICE_NAME="myservice" \
    NAMESPACE="mynamespace" \
    DNS_ZONE="estafette.io" \
    CLIENT_BODY_TIMEOUT="60s" \
    CLIENT_HEADER_TIMEOUT="60s" \
    CLIENT_BODY_BUFFER_SIZE="128k" \
    CLIENT_MAX_BODY_SIZE="0" \
    KEEPALIVE_TIMEOUT="10s" \
    KEEPALIVE_TIMEOUT_HEADER="10" \
    SEND_TIMEOUT="60s" \
    PROXY_REQUEST_BUFFERING="off" \
    PROXY_BUFFERING="on" \
    PROXY_BUFFERS_NUMBER="16" \
    PROXY_BUFFERS_SIZE="64k" \
    PROXY_BUFFER_SIZE="16k" \
    PROXY_CONNECT_TIMEOUT="60s" \
    PROXY_SEND_TIMEOUT="60s" \
    PROXY_READ_TIMEOUT="60s" \
    ENFORCE_HTTPS="true" \
    PROMETHEUS_METRICS_PORT="9101" \
    DEFAULT_BUCKETS="{0.005, 0.01, 0.02, 0.03, 0.05, 0.075, 0.1, 0.2, 0.3, 0.4, 0.5, 0.75, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 7.5, 10, 15, 20, 30, 60, 120}" \
    NGINX_CONF_TMPL_PATH="/tmpl/nginx.conf.tmpl" \
    NGINX_CORS_CONF_TMPL_PATH="/tmpl/cors.conf.tmpl" \
    PROMETHEUS_LUA_TMPL_PATH="/tmpl/prometheus.lua.tmpl" \
    SSL_PROTOCOLS="TLSv1.2" \
    SETUP_CORS="false" \
    CORS_ALLOWED_ORIGINS="*" \
    CORS_MAX_AGE="86400" \
    GRACEFUL_SHUTDOWN_DELAY_SECONDS="15" \
    UPSTREAM_KEEPALIVE_CONNECTIONS="32" \
    JAEGER_AGENT_HOST="localhost" \
    JAEGER_AGENT_PORT="6831" \
    JAEGER_SAMPLER_TYPE="remote" \
    JAEGER_SAMPLER_PARAM="0.001" \
    JAEGER_REPORTER_LOG_SPANS="false" \
    LD_LIBRARY_PATH="/usr/local/lib"

ENTRYPOINT ["/docker-entrypoint.sh"]

# Reset change of stopsignal in openresty container at https://github.com/openresty/docker-openresty/blob/master/alpine/Dockerfile#L124
STOPSIGNAL SIGTERM