#!/usr/bin/env bash
set -Eeuo pipefail

RPC="${RPC:-http://127.0.0.1:26657}"

status=$(curl -sf "$RPC/status" 2>/dev/null || true)
if [[ -z "$status" ]]; then
  exit 1
fi

catching=$(echo "$status" | jq -r '.result.sync_info.catching_up' 2>/dev/null || echo "true")
if [[ "$catching" == "false" ]]; then
  exit 0
fi

exit 1
