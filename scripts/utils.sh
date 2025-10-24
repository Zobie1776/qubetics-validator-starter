#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_ENV_FILE="${REPO_ROOT}/.env"

load_env_file() {
  local env_file="${1:-$DEFAULT_ENV_FILE}"
  if [[ -f "$env_file" ]]; then
    # shellcheck disable=SC1090
    source "$env_file"
  fi
}

load_env_file "$DEFAULT_ENV_FILE"

REPORTS_DIR="${REPORTS_DIR:-${REPO_ROOT}/.reports}"
mkdir -p "$REPORTS_DIR"

LOG_FILE="${LOG_FILE:-${REPORTS_DIR}/run.log}"
touch "$LOG_FILE"

NETWORK_PROFILE="${NETWORK_PROFILE:-mainnet}"
CHAIN_ID="${CHAIN_ID:-qubetics-1}"
RPC_PORT="${RPC_PORT:-26657}"
P2P_PORT="${P2P_PORT:-26656}"
GRPC_PORT="${GRPC_PORT:-9090}"
API_PORT="${API_PORT:-1317}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-26660}"
LOG_LEVEL="${LOG_LEVEL:-info}"

say() {
  local msg="${1:-}"
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$msg" | tee -a "$LOG_FILE"
}

die() {
  local msg="${1:-unknown error}"; local code="${2:-1}"
  say "ERROR: $msg"
  exit "$code"
}

require_cmd() {
  local cmd="${1:-}"; command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' not found"
}

require_env() {
  local var="${1:-}"
  if [[ -z "$var" ]]; then
    die "require_env expects a variable name"
  fi
  if [[ -z "${!var:-}" ]]; then
    die "Required environment variable '$var' is not set"
  fi
}

confirm() {
  local prompt="${1:-Are you sure? [y/N]}"
  read -r -p "$prompt " reply || reply=""
  case "${reply}" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) say "Action cancelled by user"; return 1 ;;
  esac
}

json() {
  local filter="${1:-.}"; shift || true
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

COMMON_ARGS=()

parse_common_args() {
  COMMON_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --network)
        NETWORK_PROFILE="$2"; export NETWORK_PROFILE; shift 2 ;;
      --env-file)
        load_env_file "$2"; shift 2 ;;
      --help)
        COMMON_ARGS=("$1" "${@:2}")
        return 1 ;;
      --*)
        COMMON_ARGS=("$@")
        return 0 ;;
      *)
        COMMON_ARGS=("$@")
        return 0 ;;
    esac
  done
  COMMON_ARGS=()
  return 0
}

export NETWORK_PROFILE CHAIN_ID RPC_PORT P2P_PORT GRPC_PORT API_PORT PROMETHEUS_PORT LOG_LEVEL
