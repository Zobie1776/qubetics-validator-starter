#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "Upgrade must be run as root"
  fi
}

require_root

HOME_DIR="${HOME_DIR:-/data/.qubeticsd}"
SERVICE_NAME="qubeticschain.service"
BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/.backups/qubetics}"
mkdir -p "$BACKUP_ROOT" "$REPORTS_DIR"

TIMESTAMP="$(date -u +'%Y%m%d%H%M%S')"
BACKUP_FILE="$BACKUP_ROOT/${TIMESTAMP}.tar.gz"

say "Stopping $SERVICE_NAME"
systemctl stop "$SERVICE_NAME" || true

say "Creating configuration backup at $BACKUP_FILE"
BACKUP_ITEMS=()
if [[ -d "/data/config" ]]; then
  BACKUP_ITEMS+=("/data/config")
fi
if [[ -f "$HOME_DIR/config/priv_validator_key.json" ]]; then
  BACKUP_ITEMS+=("$HOME_DIR/config/priv_validator_key.json")
fi
if [[ -f "$HOME_DIR/config/priv_validator_state.json" ]]; then
  BACKUP_ITEMS+=("$HOME_DIR/config/priv_validator_state.json")
fi
if [[ -f "$HOME_DIR/config/node_key.json" ]]; then
  BACKUP_ITEMS+=("$HOME_DIR/config/node_key.json")
fi

if [[ ${#BACKUP_ITEMS[@]} -gt 0 ]]; then
  tar -czf "$BACKUP_FILE" "${BACKUP_ITEMS[@]}"
else
  say "Warning: nothing to backup"
fi

VERSION="${VERSION:-}"
if [[ -n "$VERSION" ]]; then
  say "Requested qubeticsd upgrade to $VERSION"
  if command -v git >/dev/null 2>&1 && command -v go >/dev/null 2>&1; then
    TMP_DIR="$(mktemp -d)"
    cleanup_tmp() {
      rm -rf "$TMP_DIR"
    }
    trap cleanup_tmp EXIT
    git clone --depth 1 --branch "$VERSION" https://github.com/Qubetics/qubetics "$TMP_DIR/qubetics" 2>/dev/null || {
      say "Warning: unable to clone qubetics repository at $VERSION"
    }
    if [[ -d "$TMP_DIR/qubetics" ]]; then
      pushd "$TMP_DIR/qubetics" >/dev/null
      make install || say "Warning: make install failed"
      popd >/dev/null
    fi
    cleanup_tmp
    trap - EXIT
  else
    say "Go toolchain not available. Skipping source build."
  fi
else
  say "No VERSION provided. Skipping binary replacement."
fi

say "Starting $SERVICE_NAME"
systemctl start "$SERVICE_NAME" || true
sleep 5

STATUS_JSON="$(curl -s http://127.0.0.1:26657/status || echo '{}')"
HEIGHT="$(printf '%s' "$STATUS_JSON" | json '.result.sync_info.latest_block_height' 2>/dev/null || echo 'unknown')"
NEW_VERSION="$(qubeticsd version 2>/dev/null || echo 'unknown')"

REPORT_FILE="${REPORTS_DIR}/upgrade.md"
cat <<REPORT > "$REPORT_FILE"
# Upgrade Report

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Requested version: ${VERSION:-current}
- Running version: $NEW_VERSION
- Latest block height: $HEIGHT
- Backup: $BACKUP_FILE
REPORT

say "Upgrade complete. Report written to $REPORT_FILE"
