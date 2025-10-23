#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

REPORT_FILE="${REPORTS_DIR}/harden.md"
SERVICE_NAME="qubeticschain.service"
OVERRIDE_DIR="/etc/systemd/system/${SERVICE_NAME}.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"
FAIL2BAN_JAIL="/etc/fail2ban/jail.d/sshd.local"

if [[ $EUID -ne 0 ]]; then
  die "Hardening requires root access"
fi

mkdir -p "$OVERRIDE_DIR" "$(dirname "$FAIL2BAN_JAIL")" "$REPORTS_DIR"

cat <<'CONF' > "$OVERRIDE_FILE"
[Service]
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=yes
RestrictSUIDSGID=true
CapabilityBoundingSet=
LimitNOFILE=65535
Restart=always
RestartSec=3
CONF

say "Systemd override written to $OVERRIDE_FILE"

systemctl daemon-reload || true
systemctl restart "$SERVICE_NAME" || true

say "Configuring UFW defaults"
ufw default deny incoming >/dev/null 2>&1 || true
ufw default allow outgoing >/dev/null 2>&1 || true
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw allow 26656/tcp >/dev/null 2>&1 || true
ufw deny 26657/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

say "Configuring fail2ban"
cat <<'JAIL' > "$FAIL2BAN_JAIL"
[sshd]
enabled = true
maxretry = 5
findtime = 10m
bantime = 1h
JAIL

systemctl enable --now fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban >/dev/null 2>&1 || true

UFW_STATUS="$(ufw status || true)"
FAIL2BAN_STATUS="$(systemctl status fail2ban --no-pager 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' || true)"

cat <<REPORT > "$REPORT_FILE"
# Harden Report

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Systemd override: $OVERRIDE_FILE
- Fail2ban jail: $FAIL2BAN_JAIL

## UFW

```
$UFW_STATUS
```

## Fail2ban

```
$FAIL2BAN_STATUS
```
REPORT

say "Hardening complete. Summary written to $REPORT_FILE"
