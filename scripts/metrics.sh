#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --rpc <url>            Override RPC endpoint (default http://127.0.0.1:${RPC_PORT})
  --network <profile>    Network profile context
  --env-file <path>      Load variables from a file
  --help                 Show this message
USAGE
}

RPC="${RPC:-http://127.0.0.1:${RPC_PORT}}"
REPORT_FILE="${REPORTS_DIR}/metrics.md"
mkdir -p "$REPORTS_DIR"

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

set -- "${COMMON_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc)
      RPC="$2"; shift 2 ;;
    --help)
      usage; exit 0 ;;
    --*)
      die "Unknown flag $1" ;;
    *)
      break ;;
  esac
done

require_cmd curl
require_cmd jq

STATUS_JSON="$(curl -fsS "$RPC/status" 2>/dev/null || echo '{}')"
HEIGHT="$(printf '%s' "$STATUS_JSON" | json '.result.sync_info.latest_block_height' 2>/dev/null || echo 'unknown')"
CATCHING="$(printf '%s' "$STATUS_JSON" | json '.result.sync_info.catching_up' 2>/dev/null || echo 'unknown')"
PEERS="$(printf '%s' "$STATUS_JSON" | jq -r '.result.peers | length' 2>/dev/null || echo 'unknown')"

[[ "$HEIGHT" == "null" || -z "$HEIGHT" ]] && HEIGHT="unknown"
[[ "$CATCHING" == "null" || -z "$CATCHING" ]] && CATCHING="unknown"
[[ "$PEERS" == "null" || -z "$PEERS" ]] && PEERS="unknown"

cat <<REPORT > "$REPORT_FILE"
# Metrics Snapshot

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Height: $HEIGHT
- catching_up: $CATCHING
- Peer count: $PEERS

## Telemetry Tips

1. Enable Prometheus metrics in app.toml by setting [telemetry].prometheus = true and updating the listen address.
2. Allow trusted scrapers (for example sentry nodes) to reach port 26660 via UFW rules.
3. Scrape with Prometheus by adding the node to a job target list.
4. Use Grafana dashboards or Cosmos SDK community panels to visualise validator performance.
REPORT

say "Height: $HEIGHT | catching_up: $CATCHING | peers: $PEERS"
say "Metrics guidance written to $REPORT_FILE"
