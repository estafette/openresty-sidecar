FROM gcc:9.2.0

ARG OPENTRACING_CPP_VERSION="v1.6.0"
ARG OPENTRACING_NGINX_VERSION="v0.9.0"
ARG JAEGER_CPP_VERSION="v0.5.0"

# install cmake
RUN wget https://github.com/Kitware/CMake/releases/download/v3.16.2/cmake-3.16.2-Linux-x86_64.sh \
    -q -O /tmp/cmake-install.sh \
    && chmod u+x /tmp/cmake-install.sh \
    && mkdir /usr/bin/cmake \
    && /tmp/cmake-install.sh --skip-license --prefix=/usr/bin/cmake \
    && rm /tmp/cmake-install.sh

ENV PATH="/usr/bin/cmake/bin:${PATH}"

# clone repositories to build
RUN git clone -q -b ${OPENTRACING_CPP_VERSION} https://github.com/opentracing/opentracing-cpp.git \
    && git clone -q -b ${OPENTRACING_NGINX_VERSION} https://github.com/opentracing-contrib/nginx-opentracing.git \
    && git clone -q -b ${JAEGER_CPP_VERSION} https://github.com/jaegertracing/jaeger-client-cpp.git

# build opentracing-cpp
RUN cd opentracing-cpp \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make \
    && make install \
    && cd ../..

# build jaeger-client-cpp
RUN cd jaeger-client-cpp \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make \
    && make install \
    && cd ../..

# # build nginx-opentracing
# RUN cd nginx-opentracing \
#     && mkdir build \
#     && cd build \
#     && cmake .. \
#     && make \
#     && make install \
#     && cd ../..

RUN ls -latr opentracing-cpp/build/output \
    && ls -latr jaeger-client-cpp/build/output \
    # && ls -latr nginx-opentracing

FROM openresty/openresty:1.15.8.2-6-alpine

LABEL maintainer="estafette.io" \
      description="The openresty-sidecar runs next to estafette-ci-api to handle TLS offloading"

# install inotifywait to detect changes to config and certificates
RUN apk --update upgrade && \
    apk add --update inotify-tools gettext && \
    rm -rf /var/cache/apk/*

# Copy nginx configuration files
# COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY nginx.vh.default.conf /etc/nginx/conf.d/default.conf

COPY --from=0 /opentracing-cpp/build/output/libopentracing.so /usr/local/lib/libopentracing.so
COPY --from=0 /opentracing-cpp/build/output/libopentracing_mocktracer.so /usr/local/lib/libopentracing_mocktracer.so
COPY --from=0 /jaeger-client-cpp/build/output/libjaegertracing_plugin.linux_amd64.so /usr/local/lib/libjaegertracing_plugin.so

EXPOSE 80 81 82 443 9101

COPY nginx.conf /tmpl/nginx.conf.tmpl
COPY cors.conf /tmpl/cors.conf.tmpl
COPY lua-init.conf /usr/local/openresty/nginx/conf/includes/lua-init.conf
COPY prometheus.lua /tmpl/prometheus.lua.tmpl
COPY jaeger-nginx-config.yaml /tmpl/jaeger-nginx-config.yaml.tmpl
COPY ./docker-entrypoint.sh /

RUN chmod 500 /docker-entrypoint.sh

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
    CLIENT_MAX_BODY_SIZE="128M" \
    KEEPALIVE_TIMEOUT="10s" \
    KEEPALIVE_TIMEOUT_HEADER="10" \
    SEND_TIMEOUT="60s" \
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
    JAEGER_REPORTER_LOG_SPANS="false"

ENTRYPOINT ["/docker-entrypoint.sh"]

# Reset change of stopsignal in openresty container at https://github.com/openresty/docker-openresty/blob/master/alpine/Dockerfile#L124
STOPSIGNAL SIGTERM
