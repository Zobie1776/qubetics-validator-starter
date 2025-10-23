#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

WORKDIR="${WORKDIR:-${HOME}/nodes/qubetics}"
MONIKER_INPUT="${1:-${MONIKER:-Q-Sync}}"
MONIKER="${MONIKER_INPUT:-Q-Sync}"
REPO_URL="https://github.com/Qubetics/qubetics-mainnetnode-script"
REPO_DIR="$WORKDIR/qubetics-mainnetnode-script"
SERVICE_NAME="qubeticschain.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
NODE_HOME="/data/.qubeticsd"
REPORT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/.reports"
REPORT_FILE="$REPORT_DIR/bootstrap.md"

say "Starting Qubetics bootstrap phase (Q-Sync)"

if [[ $EUID -ne 0 ]]; then
  die "Bootstrap must be run as root"
fi

mkdir -p "$WORKDIR" "$REPORT_DIR" /data "$NODE_HOME"

say "Updating apt repositories"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null

say "Installing required packages"
apt-get install -y git curl jq ufw fail2ban build-essential unzip lz4 >/dev/null

say "Configuring UFW defaults"
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow 26656/tcp >/dev/null 2>&1 || true
ufw deny 26657/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

say "Enabling fail2ban"
systemctl enable --now fail2ban >/dev/null 2>&1 || true

say "Cloning validator scripts from upstream"
if [[ -d "$REPO_DIR/.git" ]]; then
  git -C "$REPO_DIR" fetch --all >/dev/null 2>&1 || true
  git -C "$REPO_DIR" reset --hard origin/main >/dev/null 2>&1 || true
else
  mkdir -p "$WORKDIR"
  if git clone "$REPO_URL" "$REPO_DIR" >/dev/null 2>&1; then
    say "Upstream repository cloned"
  else
    say "Warning: unable to clone upstream repository right now. Re-run bootstrap once network access is available."
  fi
fi

say "Running official install scripts"
if [[ -x "$REPO_DIR/fast-sync.sh" ]]; then
  bash "$REPO_DIR/fast-sync.sh" || die "Fast-sync script failed"
elif [[ -x "$REPO_DIR/ubuntu.sh" ]]; then
  bash "$REPO_DIR/ubuntu.sh" || die "Ubuntu install script failed"
else
  say "Warning: no known upstream installer found; assuming qubeticsd already installed"
fi

say "Creating qubetics systemd service"
cat <<SERVICE | tee "$SERVICE_FILE" >/dev/null
[Unit]
Description=Qubetics Validator Node (Q-Sync)
After=network-online.target
Wants=network-online.target

[Service]
User=root
Type=simple
ExecStart=/usr/local/bin/qubeticsd start --home $NODE_HOME --moniker "$MONIKER"
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

say "Waiting for node RPC to become available"
ATTEMPTS=0
until curl -sf http://127.0.0.1:26657/status >/dev/null; do
  sleep 5
  ATTEMPTS=$((ATTEMPTS + 1))
  if (( ATTEMPTS > 60 )); then
    die "RPC endpoint did not become ready in time"
  fi
  say "... still waiting for RPC (attempt $ATTEMPTS)"
done

NODE_ID="$(qubeticsd tendermint show-node-id 2>/dev/null || echo 'unknown')"
say "Node ID: $NODE_ID"

cat <<MARKDOWN > "$REPORT_FILE"
# Bootstrap Report

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Moniker: $MONIKER
- Node ID: $NODE_ID
- Service: $SERVICE_NAME

Next steps:
1. Securely import your validator key (mnemonic must never touch this server).
2. Run: `qubeticsd keys add validator --recover --keyring-backend file`
3. Continue with: `make finish`
MARKDOWN

say "Bootstrap completed. Validator service is running."
say "IMPORTANT: Import your validator key securely before running finish.sh"
say "Recommended command: qubeticsd keys add validator --recover --keyring-backend file"
