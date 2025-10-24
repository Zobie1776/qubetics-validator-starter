#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --output <dir>         Backup destination directory (default $BACKUP_DIR)
  --home <path>          Qubetics home directory
  --passphrase <value>   Override BACKUP_PASSPHRASE for encryption
  --network <profile>    Network profile context
  --env-file <path>      Load environment variables from a file
  --help                 Show this message
USAGE
}

BACKUP_DIR="${BACKUP_DIR:-${HOME}/.backups/qubetics}"
HOME_DIR="${HOME_DIR:-/data/.qubeticsd}"
BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE:-}"

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

set -- "${COMMON_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      BACKUP_DIR="$2"; shift 2 ;;
    --home)
      HOME_DIR="$2"; shift 2 ;;
    --passphrase)
      BACKUP_PASSPHRASE="$2"; shift 2 ;;
    --help)
      usage; exit 0 ;;
    --*)
      die "Unknown flag $1" ;;
    *)
      break ;;
  esac
done

require_cmd tar

mkdir -p "$BACKUP_DIR"
TIMESTAMP="$(date -u +'%Y%m%d%H%M%S')"
ARCHIVE_NAME="qubetics-backup-${CHAIN_ID}-${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${BACKUP_DIR%/}/${ARCHIVE_NAME}"

if [[ $EUID -ne 0 ]]; then
  die "backup.sh must be run as root"
fi

say "Creating backup at $ARCHIVE_PATH"
if ! tar -czf "$ARCHIVE_PATH" \
  -C "$HOME_DIR" config/priv_validator_key.json config/priv_validator_state.json config/node_key.json config/genesis.json config/app.toml config/config.toml data; then
  die "Backup failed"
fi

if [[ -n "$BACKUP_PASSPHRASE" ]]; then
  require_cmd openssl
  ENCRYPTED_PATH="${ARCHIVE_PATH}.enc"
  say "Encrypting backup with openssl"
  openssl enc -aes-256-cbc -pbkdf2 -salt -in "$ARCHIVE_PATH" -out "$ENCRYPTED_PATH" -pass "pass:$BACKUP_PASSPHRASE"
  rm -f "$ARCHIVE_PATH"
  ARCHIVE_PATH="$ENCRYPTED_PATH"
fi

REPORT_FILE="${REPORTS_DIR}/backup.md"
cat <<REPORT > "$REPORT_FILE"
# Backup Completed

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Chain: $CHAIN_ID
- Backup file: $ARCHIVE_PATH
- Encrypted: $([[ -n "$BACKUP_PASSPHRASE" ]] && echo "yes" || echo "no")
REPORT

say "Backup stored at $ARCHIVE_PATH"
say "Report written to $REPORT_FILE"
