#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --output <dir>         Directory to write snapshot files (default $SNAPSHOT_DIR)
  --home <path>          Qubetics home directory
  --retain <count>       Number of historical snapshots to retain
  --network <profile>    Network profile context
  --env-file <path>      Load environment variables from a file
  --help                 Show this help message
USAGE
}

SNAPSHOT_DIR="${SNAPSHOT_DIR:-${HOME}/.snapshots/qubetics}"
HOME_DIR="${HOME_DIR:-/data/.qubeticsd}"
RETAIN_COUNT="${SNAPSHOT_RETAIN:-5}"
SERVICE_NAME="qubeticschain.service"

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

set -- "${COMMON_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      SNAPSHOT_DIR="$2"; shift 2 ;;
    --home)
      HOME_DIR="$2"; shift 2 ;;
    --retain)
      RETAIN_COUNT="$2"; shift 2 ;;
    --help)
      usage; exit 0 ;;
    --*)
      die "Unknown flag $1" ;;
    *)
      break ;;
  esac
done

require_cmd tar
require_cmd lz4

mkdir -p "$SNAPSHOT_DIR"

if [[ $EUID -ne 0 ]]; then
  die "snapshot.sh must be run as root"
fi

TIMESTAMP="$(date -u +'%Y%m%d%H%M%S')"
ARCHIVE_NAME="qubetics-${CHAIN_ID}-${TIMESTAMP}.tar"
ARCHIVE_PATH="${SNAPSHOT_DIR%/}/${ARCHIVE_NAME}"

say "Stopping $SERVICE_NAME to ensure consistent snapshot"
systemctl stop "$SERVICE_NAME" || true
sleep 2

say "Creating snapshot archive at $ARCHIVE_PATH"
if ! tar -cf "$ARCHIVE_PATH" -C "$HOME_DIR" data config/priv_validator_state.json config/priv_validator_key.json config/node_key.json >/dev/null 2>&1; then
  say "Warning: tar reported issues. Ensure paths exist."
fi

say "Restarting $SERVICE_NAME"
systemctl start "$SERVICE_NAME" || true

COMPRESSED_PATH="${ARCHIVE_PATH}.lz4"
say "Compressing snapshot to $COMPRESSED_PATH"
if ! lz4 -9 "$ARCHIVE_PATH" "$COMPRESSED_PATH" >/dev/null 2>&1; then
  die "Failed to compress snapshot"
fi
rm -f "$ARCHIVE_PATH"

if [[ "$RETAIN_COUNT" =~ ^[0-9]+$ && "$RETAIN_COUNT" -gt 0 ]]; then
  say "Pruning snapshots older than $RETAIN_COUNT copies"
  mapfile -t snapshots < <(ls -1t "$SNAPSHOT_DIR"/*.lz4 2>/dev/null || true)
  if (( ${#snapshots[@]} > RETAIN_COUNT )); then
    for old in "${snapshots[@]:RETAIN_COUNT}"; do
      say "Removing old snapshot $old"
      rm -f "$old"
    done
  fi
fi

REPORT_FILE="${REPORTS_DIR}/snapshot-create.md"
cat <<REPORT > "$REPORT_FILE"
# Snapshot Created

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Chain: $CHAIN_ID
- Snapshot: $COMPRESSED_PATH
- Retention: $RETAIN_COUNT
REPORT

say "Snapshot created: $COMPRESSED_PATH"
say "Report written to $REPORT_FILE"
