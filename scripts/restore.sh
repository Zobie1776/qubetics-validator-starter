#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --snapshot-url <url>   Remote snapshot URL to download (required if SNAP_URL not set)
  --home <path>          Qubetics home directory
  --network <profile>    Network profile (mainnet/testnet)
  --env-file <path>      Load variables from custom env file
  --help                 Show this help
USAGE
}

HOME_DIR="${HOME_DIR:-/data/.qubeticsd}"
SNAP_URL="${SNAP_URL:-}"
BACKUP_ROOT="${BACKUP_DIR:-${HOME}/.backups/qubetics}"
SERVICE_NAME="qubeticschain.service"

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

set -- "${COMMON_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot-url)
      SNAP_URL="$2"; shift 2 ;;
    --home)
      HOME_DIR="$2"; shift 2 ;;
    --help)
      usage; exit 0 ;;
    --*)
      die "Unknown flag $1" ;;
    *)
      break ;;
  esac
done

if [[ -z "$SNAP_URL" ]]; then
  usage
  die "SNAP_URL is required"
fi

if [[ $EUID -ne 0 ]]; then
  die "Snapshot restore must be run as root"
fi

require_cmd curl
require_cmd lz4
require_cmd tar

mkdir -p "$REPORTS_DIR" "$BACKUP_ROOT"

TIMESTAMP="$(date -u +'%Y%m%d%H%M%S')"
BACKUP_FILE="$BACKUP_ROOT/pre-restore-${TIMESTAMP}.tar.gz"

say "Stopping $SERVICE_NAME"
systemctl stop "$SERVICE_NAME" || true

say "Backing up config and keys to $BACKUP_FILE"
BACKUP_ITEMS=()
[[ -d "$HOME_DIR/config" ]] && BACKUP_ITEMS+=("$HOME_DIR/config")
[[ -f "$HOME_DIR/data/priv_validator_state.json" ]] && BACKUP_ITEMS+=("$HOME_DIR/data/priv_validator_state.json")
[[ -f "$HOME_DIR/config/priv_validator_key.json" ]] && BACKUP_ITEMS+=("$HOME_DIR/config/priv_validator_key.json")
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
  STATUS_JSON="$(curl -fsS "http://127.0.0.1:${RPC_PORT}/status" 2>/dev/null || echo '{}')"
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

REPORT_FILE="${REPORTS_DIR}/restore.md"
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
