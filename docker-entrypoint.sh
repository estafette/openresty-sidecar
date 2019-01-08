#!/bin/sh
set -ex

# inspired by https://medium.com/@gchudnov/trapping-signals-in-docker-containers-7a57fdda7d86#.k9cjxrx6o

# SIGHUP-handler
sighup_handler() {
  echo "Reloading openresty configuration and certificates..."
  /usr/local/openresty/bin/openresty -s reload
}

# SIGTERM-handler
sigterm_handler() {
  # kubernetes sends a sigterm, where openresty needs SIGQUIT for graceful shutdown
  echo "Gracefully shutting down openresty..."
  /usr/local/openresty/bin/openresty -s quit
  echo "Finished shutting down openresty!"

  # stop inotifywait
  inotifywait_pid=$(pgrep inotifywait)
  echo "Received SIGTERM, killing inotifywait with pid $inotifywait_pid..."
  kill -SIGTERM "$inotifywait_pid"
  wait "$inotifywait_pid"
  echo "Killed inotifywait"
}

# setup handlers
echo "Setting up signal handlers..."
trap 'kill ${!}; sighup_handler' 1 # SIGHUP
trap 'kill ${!}; sigterm_handler' 15 # SIGTERM

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
cat ${NGINX_CONF_TMPL_PATH} | envsubst \$OFFLOAD_TO_HOST,\$OFFLOAD_TO_PORT,\$OFFLOAD_TO_PROTO,\$HEALT_CHECK_PATH,\$ALLOW_CIDRS,\$SERVICE_NAME,\$NAMESPACE,\$DNS_ZONE,\$CLIENT_BODY_TIMEOUT,\$CLIENT_HEADER_TIMEOUT,\$CLIENT_BODY_BUFFER_SIZE,\$KEEPALIVE_TIMEOUT,\$KEEPALIVE_REQUESTS,\$SEND_TIMEOUT,\$PROXY_CONNECT_TIMEOUT,\$PROXY_SEND_TIMEOUT,\$PROXY_READ_TIMEOUT,\$PROMETHEUS_METRICS_PORT,\$SSL_PROTOCOLS > /usr/local/openresty/nginx/conf/nginx.conf

# substitute envvars in prometheus.lua
echo "Generating prometheus.lua..."
mkdir -p /lua-modules
cat ${PROMETHEUS_LUA_TMPL_PATH} | envsubst \$DEFAULT_BUCKETS > /lua-modules/prometheus.lua

# watch for ssl certificate changes
init_inotifywait() {
  echo "Starting inotifywait to detect changes in certificates..."
  while inotifywait -e modify,move,create,delete /etc/ssl/private/; do
    echo "Files in /etc/ssl/private changed, reloading nginx..."
    nginx -s reload
  done
}
init_inotifywait &

# run openresty
echo "Starting openresty..."
/usr/local/openresty/bin/openresty &

# wait forever until sigterm_handler stops all background processes
while true
do
  tail -f /dev/null & wait ${!}
done
