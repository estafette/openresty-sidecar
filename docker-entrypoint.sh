#!/bin/bash
set -e

# inspired by https://medium.com/@gchudnov/trapping-signals-in-docker-containers-7a57fdda7d86#.k9cjxrx6o

# SIGTERM-handler
sigterm_handler() {
  echo "Received SIGTERM, stopping inotify process..."
  kill $inotify_pid

  # kubernetes sends a sigterm, where openresty needs SIGQUIT for graceful shutdown
  echo "Gracefully shutting down openresty in ${GRACEFUL_SHUTDOWN_DELAY_SECONDS}s..."
  sleep $GRACEFUL_SHUTDOWN_DELAY_SECONDS
  /usr/local/openresty/bin/openresty -s quit
  wait $openresty_pid
  exit
}

# enforce https
if [ "${ENFORCE_HTTPS}" != "true" ]
then
  proxy_pass_default_server='location / { \
      proxy_pass http://${OFFLOAD_TO_HOST}:${OFFLOAD_TO_PORT}; \
    }'
  sed -i "s#return 301 https://\$host\$request_uri;#${proxy_pass_default_server}#g" ${NGINX_CONF_TMPL_PATH}
fi

# substitute envvars in nginx.conf
echo "Generating nginx.conf..."
cat ${NGINX_CONF_TMPL_PATH} | envsubst \$OFFLOAD_TO_HOST,\$OFFLOAD_TO_PORT,\$OFFLOAD_TO_PROTO,\$HEALT_CHECK_PATH,\$ALLOW_CIDRS,\$SERVICE_NAME,\$NAMESPACE,\$DNS_ZONE,\$CLIENT_BODY_TIMEOUT,\$CLIENT_HEADER_TIMEOUT,\$CLIENT_BODY_BUFFER_SIZE,\$CLIENT_MAX_BODY_SIZE,\$KEEPALIVE_TIMEOUT,\$KEEPALIVE_TIMEOUT_HEADER,\$SEND_TIMEOUT,\$PROXY_BUFFERING,\$PROXY_BUFFERS_NUMBER,\$PROXY_BUFFERS_SIZE,\$PROXY_BUFFER_SIZE,\$PROXY_CONNECT_TIMEOUT,\$PROXY_SEND_TIMEOUT,\$PROXY_READ_TIMEOUT,\$PROMETHEUS_METRICS_PORT,\$SSL_PROTOCOLS,\$UPSTREAM_KEEPALIVE_CONNECTIONS > /usr/local/openresty/nginx/conf/nginx.conf

if [ "${SETUP_CORS}" == "true" ]; then
  echo "Generating cors.conf..."
  cat ${NGINX_CORS_CONF_TMPL_PATH} | envsubst \$CORS_ALLOWED_ORIGINS,\$CORS_MAX_AGE,\$CORS_ALLOWED_CUSTOM_HEADERS > /tmpl/cors.conf
  cat /usr/local/openresty/nginx/conf/nginx.conf | awk -v file="$(cat /tmpl/cors.conf | tr '\n' ' ')" 'gsub(/\#cors/, file)1' > /tmpl/nginx.conf
  cp -f /tmpl/nginx.conf /usr/local/openresty/nginx/conf
  rm /tmpl/nginx.conf /tmpl/cors.conf
fi

# substitute envvars in prometheus.lua
echo "Generating prometheus.lua..."
mkdir -p /lua-modules
cat ${PROMETHEUS_LUA_TMPL_PATH} | envsubst \$DEFAULT_BUCKETS > /lua-modules/prometheus.lua

echo "Generating jaeger-nginx-config.yaml..."
cat /tmpl/jaeger-nginx-config.yaml.tmpl | envsubst \$JAEGER_AGENT_HOST,\$JAEGER_AGENT_PORT,\$JAEGER_SAMPLER_TYPE,\$JAEGER_SAMPLER_PARAM,\$JAEGER_REPORTER_LOG_SPANS,\$SERVICE_NAME > /etc/jaeger-nginx-config.yaml

# watch for ssl certificate changes
init_inotifywait() {
  echo "Starting inotifywait to detect changes in certificates..."
  while inotifywait -e modify,move,create,delete /etc/ssl/private/; do
    echo "Files in /etc/ssl/private changed, reloading nginx..."
    nginx -s reload
  done
}
init_inotifywait &
inotify_pid=${!}

# run openresty
echo "Starting openresty..."
/usr/local/openresty/bin/openresty &
openresty_pid=${!}

# setup handlers
echo "Setting up signal handlers..."
trap 'sigterm_handler' 15 # SIGTERM

wait $openresty_pid