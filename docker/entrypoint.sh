#!/usr/bin/env bash
set -euo pipefail

APP_DIR=${APP_DIR:-/app}
DIST_DIR=${DIST_DIR:-/app/dist}
FILES_DIR=${FILES_DIR:-/var/www/files}
DB_DIR=${DB_DIR:-/var/www/db}
NGINX_USER=${NGINX_USER:-nginx}
PHP_V=${PHP_V:-83}

# Ensure runtime dirs
mkdir -p "$FILES_DIR" "$DB_DIR" /run/nginx /var/cache/nginx
chown -R "$NGINX_USER":"$NGINX_USER" "$FILES_DIR" "$DB_DIR" /run/nginx /var/cache/nginx || true

# Initialize SQLite database if missing
CONFIG_JSON="$DIST_DIR/config.json"
if [ -r "$CONFIG_JSON" ]; then
  DB_PATH=$(jq -r '.DB_PATH // "/var/www/db/uguu.sq3"' "$CONFIG_JSON")
  FILES_ROOT=$(jq -r '.FILES_ROOT // "/var/www/files/"' "$CONFIG_JSON")
  mkdir -p "$(dirname "$DB_PATH")" "$FILES_ROOT"
  chown -R "$NGINX_USER":"$NGINX_USER" "$(dirname "$DB_PATH")" "$FILES_ROOT" || true
  if [ ! -f "$DB_PATH" ]; then
    echo "Initializing SQLite database at $DB_PATH"
    SQLITE_SCHEMA="$APP_DIR/src/static/dbSchemas/sqlite_schema.sql"
    if [ -r "$SQLITE_SCHEMA" ]; then
      sqlite3 "$DB_PATH" < "$SQLITE_SCHEMA" || true
      chown "$NGINX_USER":"$NGINX_USER" "$DB_PATH" || true
    else
      echo "Warning: SQLite schema not found at $SQLITE_SCHEMA"
    fi
  fi
else
  echo "Warning: $CONFIG_JSON not readable; skipping DB init"
fi

# Start PHP-FPM (background)
/usr/sbin/php-fpm -F &
PHP_FPM_PID=$!

# Start Nginx (background)
nginx -g 'daemon off;' &
NGINX_PID=$!

echo "Started PHP-FPM (PID: $PHP_FPM_PID) and Nginx (PID: $NGINX_PID)"

# Wait for any process to exit
wait -n $PHP_FPM_PID $NGINX_PID 2>/dev/null || true

# If we get here, one process died - keep container alive for debugging
echo "A process exited. Keeping container alive for debugging..."
tail -f /dev/null
