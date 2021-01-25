FROM openresty/openresty:1.19.3.1-2-buster

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
    PROXY_HOST='$host' \
    HEALT_CHECK_PATH=/ \
    ALLOW_CIDRS="allow all;" \
    SERVICE_NAME="myservice" \
    NAMESPACE="mynamespace" \
    DNS_ZONE="estafette.io" \
    WORKER_PROCESSES="1" \
    WORKER_CONNECTIONS="1024" \
    WORKER_RLIMIT_NOFILE="1047552" \
    WORKER_SHUTDOWN_TIMEOUT="30s" \
    MULTI_ACCEPT="on" \
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
    UPSTREAM_KEEPALIVE_TIMEOUT="60s" \
    UPSTREAM_KEEPALIVE_REQUESTS="100" \
    JAEGER_AGENT_HOST="localhost" \
    JAEGER_AGENT_PORT="6831" \
    JAEGER_SAMPLER_TYPE="remote" \
    JAEGER_SAMPLER_PARAM="0.001" \
    JAEGER_REPORTER_LOG_SPANS="false" \
    LD_LIBRARY_PATH="/usr/local/lib"

ENTRYPOINT ["/docker-entrypoint.sh"]

# Reset change of stopsignal in openresty container at https://github.com/openresty/docker-openresty/blob/master/alpine/Dockerfile#L124
STOPSIGNAL SIGTERM