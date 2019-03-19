FROM openresty/openresty:1.13.6.2-alpine

LABEL maintainer="estafette.io" \
      description="The openresty-sidecar runs next to estafette-ci-api to handle TLS offloading"

EXPOSE 80 81 82 443 9101

COPY nginx.conf /tmpl/nginx.conf.tmpl
COPY cors.conf /tmpl/cors.conf.tmpl
COPY lua-init.conf /usr/local/openresty/nginx/conf/includes/lua-init.conf
COPY prometheus.lua /tmpl/prometheus.lua.tmpl
COPY ./docker-entrypoint.sh /

RUN chmod 500 /docker-entrypoint.sh

# install inotifywait to detect changes to config and certificates
RUN apk --update upgrade && \
    apk add --update inotify-tools gettext && \
    rm -rf /var/cache/apk/*

# runtime environment variables
ENV OFFLOAD_TO_HOST=localhost \
    OFFLOAD_TO_PORT=80 \
    OFFLOAD_TO_PROTO=http \
    HEALT_CHECK_PATH=/ \
    ALLOW_CIDRS="allow 0.0.0.0/0;" \
    SERVICE_NAME="myservice" \
    NAMESPACE="mynamespace" \
    DNS_ZONE="estafette.io" \
    CLIENT_BODY_TIMEOUT="60s" \
    CLIENT_HEADER_TIMEOUT="60s" \
    CLIENT_BODY_BUFFER_SIZE="128k" \
    CLIENT_MAX_BODY_SIZE="128M" \
    KEEPALIVE_TIMEOUT="0" \
    KEEPALIVE_TIMEOUT_HEADER="0" \
    SEND_TIMEOUT="60s" \
    PROXY_BUFFERING="on" \
    PROXY_BUFFERS_NUMBER="8" \
    PROXY_BUFFERS_SIZE="8k" \
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
    GRACEFUL_SHUTDOWN_DELAY_SECONDS="15"

ENTRYPOINT ["/docker-entrypoint.sh"]

# Reset change of stopsignal in openresty container at https://github.com/openresty/docker-openresty/blob/master/alpine/Dockerfile#L124
STOPSIGNAL SIGTERM