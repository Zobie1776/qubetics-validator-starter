#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

RPC="${RPC:-http://127.0.0.1:26657}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not available"
  exit 1
fi

if [[ -n "${HEALTHCHECK_STATUS:-}" ]]; then
  RESPONSE="$HEALTHCHECK_STATUS"
else
  RESPONSE=$(curl -sf "$RPC/status" || true)
fi

if [[ -z "$RESPONSE" ]]; then
  say "RPC status endpoint unreachable"
  exit 1
fi

CATCHING_UP=$(echo "$RESPONSE" | jq -r '.result.sync_info.catching_up' 2>/dev/null || echo "true")
if [[ "$CATCHING_UP" == "false" ]]; then
  exit 0
fi

say "Node is still catching up"
exit 1
