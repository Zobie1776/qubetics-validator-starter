#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

COMMAND="${1:-status}"
NODE_HOME="${NODE_HOME:-/data/.qubeticsd}"
CONFIG_FILE="$NODE_HOME/config/config.toml"
NGINX_SITE="/etc/nginx/sites-available/q-sync-rpc.conf"
NGINX_SITE_ENABLED="/etc/nginx/sites-enabled/q-sync-rpc.conf"
NGINX_LIMITS="/etc/nginx/conf.d/q-sync-rpc-limits.conf"

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "RPC management requires root privileges"
  fi
}

update_laddr() {
  local laddr="$1"
  if [[ -f "$CONFIG_FILE" ]]; then
    sed -i "s#^laddr = \".*\"#laddr = \"${laddr}\"#" "$CONFIG_FILE"
  fi
}

rpc_status() {
  say "RPC configuration status"
  if [[ -f "$CONFIG_FILE" ]]; then
    grep -E '^laddr' "$CONFIG_FILE" || true
  else
    say "Config file not found: $CONFIG_FILE"
  fi
  ufw status numbered 2>/dev/null | grep -E "26657|443" || true
  if [[ -L "$NGINX_SITE_ENABLED" ]]; then
    say "Nginx RPC proxy: enabled"
  else
    say "Nginx RPC proxy: disabled"
  fi
  if curl -sf http://127.0.0.1:26657/status >/dev/null; then
    say "Local RPC reachable"
  else
    say "Local RPC not reachable"
  fi
}

rpc_local() {
  require_root
  say "Restricting RPC to localhost"
  update_laddr "tcp://127.0.0.1:26657"
  ufw deny 26657/tcp >/dev/null 2>&1 || true
  ufw --force delete allow 26657/tcp >/dev/null 2>&1 || true
  ufw reload >/dev/null 2>&1 || true
  if [[ -L "$NGINX_SITE_ENABLED" ]]; then
    rm -f "$NGINX_SITE_ENABLED"
    systemctl reload nginx >/dev/null 2>&1 || true
  fi
  say "RPC locked to localhost"
}

rpc_expose() {
  require_root
  DOMAIN="${DOMAIN:-}"
  ALLOW_IPS="${ALLOW_IPS:-}"
  [[ -z "$DOMAIN" ]] && die "DOMAIN environment variable is required for RPC exposure"
  [[ -z "$ALLOW_IPS" ]] && die "ALLOW_IPS environment variable is required (comma-separated list)"

  say "Requested RPC exposure for $DOMAIN"
  confirm "Expose RPC via https://$DOMAIN ? [y/N]" || return 1

  apt-get update -y >/dev/null
  apt-get install -y nginx >/dev/null

  mkdir -p /etc/nginx/conf.d
  cat <<CONF > "$NGINX_LIMITS"
limit_req_zone $binary_remote_addr zone=q_sync_rpc:10m rate=5r/s;
CONF

  IFS=',' read -ra IPS <<< "$ALLOW_IPS"

  CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
  if [[ ! -f "$CERT" || ! -f "$KEY" ]]; then
    say "Warning: TLS certificates not found at $CERT. Install certificates before starting nginx."
  fi

  {
    echo "server {"
    echo "    listen 443 ssl http2;"
    echo "    server_name $DOMAIN;"
    echo ""
    echo "    ssl_certificate $CERT;"
    echo "    ssl_certificate_key $KEY;"
    echo ""
    echo "    access_log /var/log/nginx/q-sync-rpc.access.log;"
    echo "    error_log /var/log/nginx/q-sync-rpc.error.log;"
    echo ""
    echo "    location /rpc/ {"
    echo "        limit_req zone=q_sync_rpc burst=10 nodelay;"
    for ip in "${IPS[@]}"; do
      ip_trimmed="${ip// /}"
      [[ -z "$ip_trimmed" ]] && continue
      echo "        allow $ip_trimmed;"
    done
    echo "        deny all;"
    echo "        proxy_pass http://127.0.0.1:26657/;"
    echo "        proxy_http_version 1.1;"
    echo "        proxy_set_header Host $host;"
    echo "        proxy_set_header X-Real-IP $remote_addr;"
    echo "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
    echo "    }"
    echo "}"
  } > "$NGINX_SITE"

  ln -sf "$NGINX_SITE" "$NGINX_SITE_ENABLED"
  update_laddr "tcp://127.0.0.1:26657"
  ufw allow 443/tcp >/dev/null 2>&1 || true
  ufw deny 26657/tcp >/dev/null 2>&1 || true
  ufw reload >/dev/null 2>&1 || true
  systemctl enable --now nginx >/dev/null 2>&1 || true
  systemctl reload nginx >/dev/null 2>&1 || true
  say "RPC exposed via nginx with allow list: $ALLOW_IPS"
}

rpc_lockdown() {
  require_root
  say "Locking down public RPC"
  rm -f "$NGINX_SITE_ENABLED" "$NGINX_SITE"
  rm -f "$NGINX_LIMITS"
  systemctl reload nginx >/dev/null 2>&1 || true
  ufw --force delete allow 443/tcp >/dev/null 2>&1 || true
  ufw deny 443/tcp >/dev/null 2>&1 || true
  rpc_local
  say "RPC exposure removed"
}

case "$COMMAND" in
  status)
    rpc_status
    ;;
  local)
    rpc_local
    ;;
  expose)
    rpc_expose
    ;;
  lockdown)
    rpc_lockdown
    ;;
  *)
    echo "Usage: $0 {status|local|expose|lockdown}"
    exit 1
    ;;
esac
