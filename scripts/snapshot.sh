#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "Snapshot restore must be run as root"
  fi
}

require_root

HOME_DIR="${HOME_DIR:-/data/.qubeticsd}"
SERVICE_NAME="qubeticschain.service"
SNAP_URL="${SNAP_URL:-}"
if [[ -z "$SNAP_URL" ]]; then
  die "SNAP_URL is required"
fi

if ! command -v lz4 >/dev/null 2>&1; then
  die "lz4 command is required"
fi

mkdir -p "$REPORTS_DIR"

TIMESTAMP="$(date -u +'%Y%m%d%H%M%S')"
BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/.backups/qubetics}"
mkdir -p "$BACKUP_ROOT"
BACKUP_FILE="$BACKUP_ROOT/snapshot-${TIMESTAMP}.tar.gz"

say "Stopping $SERVICE_NAME"
systemctl stop "$SERVICE_NAME" || true

say "Backing up config and keys"
BACKUP_ITEMS=()
if [[ -d "$HOME_DIR/config" ]]; then
  BACKUP_ITEMS+=("$HOME_DIR/config")
fi
if [[ -f "$HOME_DIR/data/priv_validator_state.json" ]]; then
  BACKUP_ITEMS+=("$HOME_DIR/data/priv_validator_state.json")
fi
if [[ ${#BACKUP_ITEMS[@]} -gt 0 ]]; then
  tar -czf "$BACKUP_FILE" "${BACKUP_ITEMS[@]}"
else
  say "Warning: nothing to backup"
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
SNAP_FILE="$TEMP_DIR/snapshot.lz4"

say "Downloading snapshot from $SNAP_URL"
if ! curl -fsSL "$SNAP_URL" -o "$SNAP_FILE"; then
  die "Failed to download snapshot from $SNAP_URL"
fi

say "Clearing old data"
rm -rf "$HOME_DIR/data" "$HOME_DIR/wasm" "$HOME_DIR/snapshots"
mkdir -p "$HOME_DIR"

say "Extracting snapshot"
lz4 -d "$SNAP_FILE" -c | tar -x -C "$HOME_DIR"

say "Starting $SERVICE_NAME"
systemctl start "$SERVICE_NAME" || true
sleep 5

LOG_OUTPUT="$(journalctl -u "$SERVICE_NAME" -n 50 --no-pager 2>/dev/null || true)"

CATCHING="true"
HEIGHT="unknown"
for attempt in $(seq 1 60); do
  sleep 10
  STATUS_JSON="$(curl -fsS http://127.0.0.1:26657/status 2>/dev/null || echo '{}')"
  CATCHING="$(printf '%s' "$STATUS_JSON" | json '.result.sync_info.catching_up' 2>/dev/null || echo 'true')"
  HEIGHT="$(printf '%s' "$STATUS_JSON" | json '.result.sync_info.latest_block_height' 2>/dev/null || echo 'unknown')"
  say "Status check #$attempt catching_up=$CATCHING height=$HEIGHT"
  if [[ "$CATCHING" == "false" ]]; then
    break
  fi
  if [[ $attempt -eq 60 ]]; then
    say "Warning: node still catching up after snapshot restore"
  fi
done

REPORT_FILE="${REPORTS_DIR}/snapshot.md"
cat <<REPORT > "$REPORT_FILE"
# Snapshot Restore

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Snapshot URL: $SNAP_URL
- Backup: $BACKUP_FILE
- catching_up: $CATCHING
- Height: $HEIGHT

## Recent Logs

```
$LOG_OUTPUT
```
REPORT

say "Snapshot restore complete. Report written to $REPORT_FILE"
