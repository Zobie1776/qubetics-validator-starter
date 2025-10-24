#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options] <command>

Commands:
  status        Show RPC binding, sync, and firewall status
  local         Lock RPC to localhost
  expose        Publish temporary HTTPS proxy with snake-oil certs
  domain        Publish TLS endpoint with LetsEncrypt (requires DOMAIN)
  lockdown      Remove proxies and close RPC ports

Options:
  --network <profile>    Network profile context (mainnet/testnet)
  --env-file <path>      Load environment variables from a file
  --rate-limit <rps>     Override RATE_LIMIT_RPS for proxies
  --allow-ips <list>     Override ALLOW_IPS for domain command
  --help                 Show this help
USAGE
}

RATE_LIMIT_RPS="${RATE_LIMIT_RPS:-5}"
ALLOW_IPS="${ALLOW_IPS:-}"
HOME_DIR="${HOME_DIR:-/data/.qubeticsd}"
CONFIG_FILE="${HOME_DIR%/}/config/config.toml"
SERVICE_NAME="qubeticschain.service"
NGINX_SITE="/etc/nginx/sites-available/qubetics-rpc"
NGINX_SITE_ENABLED="/etc/nginx/sites-enabled/qubetics-rpc"

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

set -- "${COMMON_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rate-limit)
      RATE_LIMIT_RPS="$2"; shift 2 ;;
    --allow-ips)
      ALLOW_IPS="$2"; shift 2 ;;
    --help)
      usage; exit 0 ;;
    status|local|expose|domain|lockdown)
      COMMAND="$1"; shift; break ;;
    --*)
      die "Unknown flag $1" ;;
    *)
      COMMAND="$1"; shift; break ;;
  esac
done

COMMAND="${COMMAND:-status}"

require_cmd curl
require_cmd jq

if command -v ufw >/dev/null 2>&1; then
  HAVE_UFW=1
else
  HAVE_UFW=0
fi

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "RPC management requires root privileges"
  fi
}

guard_loopback() {
  local laddr
  laddr="$(toml_get_laddr || echo '')"
  local expected="tcp://127.0.0.1:${RPC_PORT}"
  if [[ "$laddr" != "$expected" ]]; then
    say "Refusing action because RPC laddr is '$laddr' (expected $expected)."
    say "Run: make rpc-local"
    exit 1
  fi
}

ensure_config_exists() {
  mkdir -p "${HOME_DIR%/}/config"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    cat <<CFG > "$CONFIG_FILE"
[rpc]
laddr = "tcp://127.0.0.1:${RPC_PORT}"
CFG
  fi
}

set_laddr_loopback() {
  ensure_config_exists
  local tmp_file="${CONFIG_FILE}.tmp"
  local expected="tcp://127.0.0.1:${RPC_PORT}"
  awk -v expected="$expected" '
    BEGIN { in_rpc=0; set=0 }
    /^\s*\[rpc\]\s*$/ { print; in_rpc=1; next }
    in_rpc && /^\s*\[/ {
      if (!set) {
        print "laddr = \"" expected "\"";
        set=1;
      }
      in_rpc=0;
    }
    {
      if (in_rpc && /^\s*laddr\s*=/) {
        if (!set) {
          print "laddr = \"" expected "\"";
          set=1;
        }
        next;
      }
      print;
    }
    END {
      if (in_rpc && !set) {
        print "laddr = \"" expected "\"";
      }
      if (!set) {
        if (!in_rpc) {
          print "";
          print "[rpc]";
        }
        print "laddr = \"" expected "\"";
      }
    }
  ' "$CONFIG_FILE" > "$tmp_file"
  mv "$tmp_file" "$CONFIG_FILE"
}

rpc_status() {
  local laddr catching ufw_p2p ufw_rpc nginx_state status_json report_file
  report_file="${REPORTS_DIR}/rpc-status.md"
  laddr="$(toml_get_laddr || echo 'unknown')"
  status_json="$(curl -fsS "http://127.0.0.1:${RPC_PORT}/status" 2>/dev/null || echo '{}')"
  catching="$(printf '%s' "$status_json" | json '.result.sync_info.catching_up' 2>/dev/null || echo 'unknown')"
  [[ "$catching" == "null" || -z "$catching" ]] && catching="unknown"
  if (( HAVE_UFW )); then
    ufw_p2p=$(ufw status numbered 2>/dev/null | grep -F "${P2P_PORT}" || true)
    ufw_rpc=$(ufw status numbered 2>/dev/null | grep -F "${RPC_PORT}" || true)
  else
    ufw_p2p="ufw not installed"
    ufw_rpc="ufw not installed"
  fi
  if [[ -L "$NGINX_SITE_ENABLED" ]]; then
    nginx_state="enabled ($NGINX_SITE_ENABLED)"
  else
    nginx_state="disabled"
  fi

  cat <<REPORT > "$report_file"
# RPC Status

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- RPC laddr: $laddr
- catching_up: $catching
- NGINX: $nginx_state

## UFW ${P2P_PORT}
${ufw_p2p:-none}

## UFW ${RPC_PORT}
${ufw_rpc:-none}
REPORT

  say "RPC laddr: $laddr"
  say "catching_up: $catching"
  say "NGINX proxy: $nginx_state"
  say "Status report written to $report_file"
}

rpc_local() {
  require_root
  say "Enforcing loopback RPC"
  set_laddr_loopback
  systemctl restart "$SERVICE_NAME" || true
  if (( HAVE_UFW )); then
    ufw allow "${P2P_PORT}/tcp" >/dev/null 2>&1 || true
    ufw deny "${RPC_PORT}/tcp" >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
  else
    say "Warning: ufw not available; skipping firewall updates"
  fi
  rm -f "$NGINX_SITE_ENABLED"
  [[ -f "$NGINX_SITE" ]] && rm -f "$NGINX_SITE"
  if command -v nginx >/dev/null 2>&1; then
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  fi
  say "RPC locked to localhost"
}

rpc_expose() {
  require_root
  guard_loopback
  say "Configuring local HTTPS reverse proxy shell"
  if ! apt-get update -y >/dev/null 2>&1; then
    say "Warning: apt-get update failed; continuing with cached metadata"
  fi
  if ! apt-get install -y nginx ssl-cert >/dev/null 2>&1; then
    say "Warning: unable to install nginx prerequisites"
  fi

  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
  cat <<CONF > "$NGINX_SITE"
limit_req_zone \$binary_remote_addr zone=rpc:10m rate=${RATE_LIMIT_RPS}r/s;
server {
    listen 443 ssl http2 default_server;
    server_name _;

    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    location /rpc/ {
        limit_req zone=rpc burst=10 nodelay;
        deny all;
        proxy_pass http://127.0.0.1:${RPC_PORT}/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
    }
}
CONF

  ln -sf "$NGINX_SITE" "$NGINX_SITE_ENABLED"
  nginx -t
  systemctl enable --now nginx >/dev/null 2>&1 || true
  systemctl reload nginx >/dev/null 2>&1 || true
  if (( HAVE_UFW )); then
    ufw allow 443/tcp >/dev/null 2>&1 || true
  else
    say "Warning: ufw not available; skipping firewall updates"
  fi
  say "Local HTTPS proxy prepared. Install valid TLS certificates before use."
}

generate_domain_site() {
  local domain="$1"
  local allow_ips="$2"
  local cert_path="/etc/letsencrypt/live/${domain}/fullchain.pem"
  local key_path="/etc/letsencrypt/live/${domain}/privkey.pem"
  local site_file="$NGINX_SITE"
  local -a ips=()
  local trimmed
  IFS=',' read -r -a ips <<< "$allow_ips"

  {
    printf 'limit_req_zone $binary_remote_addr zone=rpc:10m rate=%sr/s;\n' "$RATE_LIMIT_RPS"
    printf 'server {\n'
    printf '    listen 443 ssl http2;\n'
    printf '    server_name %s;\n' "$domain"
    printf '    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;\n'
    printf '    ssl_certificate %s;\n' "$cert_path"
    printf '    ssl_certificate_key %s;\n' "$key_path"
    printf '    include /etc/letsencrypt/options-ssl-nginx.conf;\n'
    printf '    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;\n'
    printf '\n'
    printf '    location /rpc/ {\n'
    for ip in "${ips[@]}"; do
      trimmed="${ip// /}"
      [[ -z "$trimmed" ]] && continue
      printf '        allow %s;\n' "$trimmed"
    done
    printf '        deny all;\n'
    printf '        limit_req zone=rpc burst=10 nodelay;\n'
    printf '        proxy_pass http://127.0.0.1:%s/;\n' "${RPC_PORT}"
    printf '        proxy_http_version 1.1;\n'
    printf '        proxy_set_header Upgrade $http_upgrade;\n'
    printf '        proxy_set_header Connection "upgrade";\n'
    printf '        proxy_set_header Host $host;\n'
    printf '        proxy_set_header X-Real-IP $remote_addr;\n'
    printf '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n'
    printf '        proxy_buffering off;\n'
    printf '    }\n'
    printf '}\n'
    printf '\n'
  } > "$site_file"
}

rpc_domain() {
  require_root
  guard_loopback

  local domain="${DOMAIN:-}"
  local allow_ips_override="$ALLOW_IPS"
  local email="${EMAIL:-}"

  if [[ -z "$domain" ]]; then
    say "DOMAIN is required. Example: make rpc-domain DOMAIN=example.com EMAIL=admin@example.com"
    exit 1
  fi
  if [[ -z "$email" ]]; then
    die "EMAIL is required for certbot registration"
  fi

  local dns_records="$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd ',' - || echo '')"
  local public_ip="$(get_public_ip)"
  if [[ -n "$dns_records" && -n "$public_ip" ]]; then
    local match_found=0
    local -a dns_list=()
    IFS=',' read -ra dns_list <<< "$dns_records"
    for ip in "${dns_list[@]}"; do
      [[ "$ip" == "$public_ip" ]] && match_found=1
    done
    if [[ $match_found -eq 0 ]]; then
      say "DNS for $domain resolves to $dns_records but public IP is $public_ip"
      confirm "Continue anyway? (y/N)" || exit 1
    fi
  fi

  if ! apt-get update -y >/dev/null 2>&1; then
    say "Warning: apt-get update failed; continuing with cached metadata"
  fi
  if ! apt-get install -y nginx certbot python3-certbot-nginx >/dev/null 2>&1; then
    die "Unable to install nginx/certbot dependencies"
  fi

  certbot --nginx -d "$domain" --email "$email" --agree-tos --redirect --no-eff-email -n || die "Certbot failed. Ensure DNS is correct."

  generate_domain_site "$domain" "${allow_ips_override:-$ALLOW_IPS}"

  ln -sf "$NGINX_SITE" "$NGINX_SITE_ENABLED"
  nginx -t
  systemctl reload nginx
  if (( HAVE_UFW )); then
    ufw allow 443/tcp >/dev/null 2>&1 || true
  else
    say "Warning: ufw not available; skipping firewall updates"
  fi

  local report_file="${REPORTS_DIR}/domain_connect.md"
  local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
  local key_path="/etc/letsencrypt/live/$domain/privkey.pem"

  cat <<REPORT > "$report_file"
# Domain RPC Connect

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Domain: $domain
- DNS Records: ${dns_records:-unknown}
- Public IP: ${public_ip:-unknown}
- Allow list: ${allow_ips_override:-${ALLOW_IPS:-none}}
- Certificate: $cert_path
- Key: $key_path
- Rate limit: ${RATE_LIMIT_RPS} r/s
REPORT

  say "Domain-enabled RPC available at https://$domain/rpc/"
  say "Allow list: ${allow_ips_override:-${ALLOW_IPS:-none}}"
  say "Report written to $report_file"
}

rpc_lockdown() {
  require_root
  guard_loopback
  say "Locking down RPC domain exposure"
  rm -f "$NGINX_SITE_ENABLED"
  [[ -f "$NGINX_SITE" ]] && rm -f "$NGINX_SITE"
  if command -v nginx >/dev/null 2>&1; then
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  fi
  if (( HAVE_UFW )); then
    ufw deny 443/tcp >/dev/null 2>&1 || true
    ufw deny "${RPC_PORT}/tcp" >/dev/null 2>&1 || true
  else
    say "Warning: ufw not available; skipping firewall updates"
  fi
  set_laddr_loopback
  systemctl restart "$SERVICE_NAME" || true
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
  domain)
    rpc_domain
    ;;
  lockdown)
    rpc_lockdown
    ;;
  *)
    usage
    exit 1
    ;;
esac
