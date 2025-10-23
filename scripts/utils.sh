#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR="${LOG_DIR:-/var/log/qubetics}"
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
  LOG_DIR="/tmp/qubetics-logs"
  mkdir -p "$LOG_DIR"
fi
LOG_FILE="$LOG_DIR/q-sync.log"

say() {
  local msg="$1"
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$msg" | tee -a "$LOG_FILE"
}

die() {
  local msg="$1"
  say "ERROR: $msg"
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' not found"
}

json() {
  local filter="$1"
  shift
  jq -r "$filter" "$@"
}

confirm() {
  local prompt="${1:-Are you sure? [y/N]}"
  read -r -p "$prompt " reply
  case "${reply}" in
    [yY][eE][sS]|[yY])
      return 0
      ;;
    *)
      say "Action cancelled by user"
      return 1
      ;;
  esac
}
