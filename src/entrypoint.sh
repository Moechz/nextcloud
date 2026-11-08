#!/bin/sh
# ===========================================================================
# Nextcloud for TOS 7 - non-root entrypoint (uid 1000, no s6, no root)
#
# The upstream LinuxServer.io image starts s6-overlay as root, chowns its
# volumes to the internal "abc" user and writes to root-owned paths such as
# /app/www/public and /etc/nginx/mime.types. None of that is possible inside a
# container that already runs as uid 1000, which TOS requires. This wrapper
# therefore bypasses s6 and starts the two services the image needs directly:
#
#   * PHP-FPM  (php-fpm85 -F -y /config/php/php-fpm.conf)
#   * nginx    (nginx -c /config/nginx/nginx.conf -e stderr, HTTP on 8080)
#
# Everything writable lives in the mounted volumes:
#   /config/www/nextcloud   application code (seeded from /app/www/src once,
#                           refreshed when the image version changes)
#   /config/nginx           nginx config; the site config is seeded once and
#                           then left alone so it can be customised
#   /config/php             PHP-FPM config (regenerated on every start)
#   /config/log             nginx and PHP logs
#   /data                   user files and the SQLite database
# ===========================================================================
set -u

CONF=/config
WWW=$CONF/www/nextcloud
PORT=8080

mkdir -p "$CONF/www" "$CONF/nginx/site-confs" "$CONF/log/nginx" \
         "$CONF/log/php" "$CONF/php" /data /tmp/nginx

# ---------------------------------------------------------------- the code --
if [ ! -f "$WWW/version.php" ]; then
  echo "nextcloud: seeding the application code into $WWW ..."
  mkdir -p "$WWW"
  rsync -a /app/www/src/ "$WWW/"
else
  imgver=$(php -r 'require "/app/www/src/version.php"; echo implode(".", $OC_Version);' 2>/dev/null || true)
  instver=$(php -r 'require "/config/www/nextcloud/version.php"; echo implode(".", $OC_Version);' 2>/dev/null || true)
  if [ -n "$imgver" ] && [ "$imgver" != "$instver" ]; then
    echo "nextcloud: refreshing the code for the new image version ($instver -> $imgver)"
    rsync -a /app/www/src/ "$WWW/"
  fi
fi

# The image's own init writes this before the web installer runs; keep the
# user data outside the code directory so upgrades never touch it.
if [ ! -s "$WWW/config/config.php" ]; then
  printf '<?php\n$CONFIG = array (\n    "datadirectory" => "/data",\n);\n' > "$WWW/config/config.php"
fi

# --------------------------------------------------------------- the config --
# The stock mime.types is root-owned, so work on a copy that lives in /config.
if [ ! -f "$CONF/nginx/mime.types" ]; then
  cp /etc/nginx/mime.types "$CONF/nginx/mime.types"
  sed -i 's|\bjs;|js mjs;|g; s|\bapplication/javascript|text/javascript|g' "$CONF/nginx/mime.types"
fi

# Internal nginx config: regenerated on every start (not a user file).
cat > "$CONF/nginx/nginx.conf" <<'NGINX'
pid /tmp/nginx.pid;
daemon off;
error_log /config/log/nginx/error.log warn;
events { worker_connections 1024; }
http {
  include /config/nginx/mime.types;
  default_type application/octet-stream;
  sendfile on;
  tcp_nopush on;
  server_tokens off;
  client_max_body_size 0;
  access_log /config/log/nginx/access.log;
  client_body_temp_path /tmp/nginx/client;
  proxy_temp_path /tmp/nginx/proxy;
  fastcgi_temp_path /tmp/nginx/fastcgi;
  uwsgi_temp_path /tmp/nginx/uwsgi;
  scgi_temp_path /tmp/nginx/scgi;
  include /config/nginx/site-confs/*.conf;
}
NGINX

# The site config is seeded once from the image's own sample, with the TLS
# listeners replaced by a plain HTTP listener on 8080 and the document root
# moved to the writable code directory. If it already exists it is left alone,
# so customisations survive a restart.
if [ ! -f "$CONF/nginx/site-confs/default.conf" ]; then
  sed -e 's/^    listen 80 default_server;/    listen 8080 default_server;/' \
      -e '/listen \[::\]:80 default_server;/d' \
      -e '/listen 443 /d' \
      -e '/listen \[::\]:443 /d' \
      -e '/include \/config\/nginx\/ssl.conf;/d' \
      -e 's#root /app/www/public;#root /config/www/nextcloud;#' \
      /defaults/nginx/site-confs/default.conf.sample > "$CONF/nginx/site-confs/default.conf"
fi

# Internal PHP-FPM config: regenerated on every start. The master process runs
# as uid 1000, so no user/group switch is needed (or possible).
cat > "$CONF/php/php-fpm.conf" <<'FPM'
[global]
pid = /tmp/php-fpm.pid
error_log = /config/log/php/error.log
daemonize = no
[www]
listen = 127.0.0.1:9000
listen.allowed_clients = 127.0.0.1
pm = dynamic
pm.max_children = 8
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 4
pm.max_requests = 500
clear_env = no
env[PATH] = /lsiopy/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
php_admin_value[memory_limit] = 512M
php_admin_value[upload_max_filesize] = 16G
php_admin_value[post_max_size] = 16G
php_admin_value[max_execution_time] = 3600
FPM

# --------------------------------------------------------------- the start --
/usr/sbin/php-fpm85 -F -y "$CONF/php/php-fpm.conf" &
exec /usr/sbin/nginx -c "$CONF/nginx/nginx.conf" -e stderr
