#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
fi

REPORTS_DIR="${REPORTS_DIR:-${REPO_ROOT}/.reports}"
mkdir -p "$REPORTS_DIR"

LOG_FILE="${LOG_FILE:-${REPORTS_DIR}/run.log}"
touch "$LOG_FILE"

say() {
  local msg="${1:-}"
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$msg" | tee -a "$LOG_FILE"
}

die() {
  local msg="${1:-unknown error}"
  say "ERROR: $msg"
  exit 1
}

require_cmd() {
  local cmd="${1:-}"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' not found"
}

confirm() {
  local prompt="${1:-Are you sure? [y/N]}"
  read -r -p "$prompt " reply || reply=""
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

json() {
  local filter="${1:-.}"
  shift || true
  jq -r "$filter" "$@"
}

get_public_ip() {
  curl -fsS https://ifconfig.me || curl -fsS https://api.ipify.org || echo ""
}

toml_get_laddr() {
  local home_dir="${HOME_DIR:-/data/.qubeticsd}"
  local config_file="${home_dir%/}/config/config.toml"
  [[ -f "$config_file" ]] || return 1

  awk '
    $0 ~ /^\s*\[/{section=""}
    $0 ~ /^\s*\[rpc\]\s*/{section="rpc"; next}
    section == "rpc" && $0 ~ /^\s*laddr\s*=\s*/ {
      match($0, /"([^"]+)"/, m)
      if (m[1] != "") {
        print m[1]
        exit
      }
    }
  ' "$config_file"
}
