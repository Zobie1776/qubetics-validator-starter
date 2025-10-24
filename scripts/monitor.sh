#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --rpc <url>            Local Tendermint RPC endpoint
  --reference <url>      Reference RPC endpoint for height comparison
  --network <profile>    Network profile context
  --env-file <path>      Load environment variables from a file
  --help                 Show this message
USAGE
}

RPC="${RPC:-http://127.0.0.1:${RPC_PORT}}"
REFERENCE_RPC="${REFERENCE_RPC:-}"
BLOCK_LAG_THRESHOLD="${BLOCK_LAG_THRESHOLD:-20}"
PEER_MINIMUM="${PEER_MINIMUM:-8}"
DISK_WARN_GB="${DISK_WARN_GB:-20}"
MEMORY_WARN_PERCENT="${MEMORY_WARN_PERCENT:-85}"
CPU_WARN_PERCENT="${CPU_WARN_PERCENT:-85}"

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

set -- "${COMMON_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc)
      RPC="$2"; shift 2 ;;
    --reference)
      REFERENCE_RPC="$2"; shift 2 ;;
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

say "Collecting monitor metrics"
LOCAL_STATUS="$(curl -fsS "$RPC/status" 2>/dev/null || echo '{}')"
LOCAL_HEIGHT="$(printf '%s' "$LOCAL_STATUS" | json '.result.sync_info.latest_block_height // 0' 2>/dev/null || echo 0)"
N_PEERS="$(printf '%s' "$LOCAL_STATUS" | json '.result.peers | length' 2>/dev/null || echo 0)"
CATCHING_UP="$(printf '%s' "$LOCAL_STATUS" | json '.result.sync_info.catching_up' 2>/dev/null || echo 'true')"

if [[ -n "$REFERENCE_RPC" ]]; then
  REFERENCE_STATUS="$(curl -fsS "$REFERENCE_RPC/status" 2>/dev/null || echo '{}')"
  REFERENCE_HEIGHT="$(printf '%s' "$REFERENCE_STATUS" | json '.result.sync_info.latest_block_height // 0' 2>/dev/null || echo 0)"
else
  REFERENCE_HEIGHT="$LOCAL_HEIGHT"
fi

LAG=$(( REFERENCE_HEIGHT - LOCAL_HEIGHT ))
[[ $LAG -lt 0 ]] && LAG=0

DISK_FREE_GB=$(df -BG /data 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}' || echo 0)
MEM_USED_PERCENT=$(free | awk '/Mem:/ { printf "%.0f", ($3/$2)*100 }' || echo 0)
CPU_COUNT=$(nproc 2>/dev/null || echo 1)
LOAD_AVG=$(uptime | awk -F'load average: ' '{print $2}' | cut -d, -f1 | tr -d ' ')
CPU_USED_PERCENT=$(awk -v load="${LOAD_AVG:-0}" -v cpus="$CPU_COUNT" 'BEGIN { if (cpus <= 0) cpus = 1; printf "%.0f", (load/cpus)*100 }')

alerts=()

if [[ "$CATCHING_UP" == "true" || $LAG -gt $BLOCK_LAG_THRESHOLD ]]; then
  alerts+=("Block lag detected: $LAG blocks (threshold $BLOCK_LAG_THRESHOLD)")
fi
if (( N_PEERS < PEER_MINIMUM )); then
  alerts+=("Peer count low: $N_PEERS (min $PEER_MINIMUM)")
fi
if (( DISK_FREE_GB < DISK_WARN_GB )); then
  alerts+=("Disk space low: ${DISK_FREE_GB}G free (<${DISK_WARN_GB}G)")
fi
if (( MEM_USED_PERCENT > MEMORY_WARN_PERCENT )); then
  alerts+=("Memory usage high: ${MEM_USED_PERCENT}% (> ${MEMORY_WARN_PERCENT}%)")
fi
if (( CPU_USED_PERCENT > CPU_WARN_PERCENT )); then
  alerts+=("CPU usage high: ${CPU_USED_PERCENT}% (> ${CPU_WARN_PERCENT}%)")
fi

alerts_json=$(printf '%s\n' "${alerts[@]}" | jq -R -s 'split("\n") | map(select(length>0))')

REPORT_FILE="${REPORTS_DIR}/monitor.json"
cat <<JSON > "$REPORT_FILE"
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "chain_id": "$CHAIN_ID",
  "local_height": $LOCAL_HEIGHT,
  "reference_height": $REFERENCE_HEIGHT,
  "lag": $LAG,
  "catching_up": "$CATCHING_UP",
  "peers": $N_PEERS,
  "disk_free_gb": $DISK_FREE_GB,
  "memory_used_percent": $MEM_USED_PERCENT,
  "cpu_used_percent": $CPU_USED_PERCENT,
  "alerts": $alerts_json
}
JSON

if (( ${#alerts[@]} > 0 )); then
  say "Alerts triggered: ${alerts[*]}"
  MESSAGE="Qubetics monitor alerts on $(hostname): ${alerts[*]}"
  if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
    curl -fsS -X POST -H 'Content-type: application/json' --data "{\"text\":\"$MESSAGE\"}" "$SLACK_WEBHOOK_URL" >/dev/null || true
  fi
  if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
    curl -fsS -H 'Content-Type: application/json' -X POST --data "{\"content\":\"$MESSAGE\"}" "$DISCORD_WEBHOOK_URL" >/dev/null || true
  fi
  if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d chat_id="$TELEGRAM_CHAT_ID" -d text="$MESSAGE" >/dev/null || true
  fi
else
  say "All metrics within thresholds"
fi

say "Monitor report written to $REPORT_FILE"
