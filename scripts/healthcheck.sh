#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

RPC="${RPC:-http://127.0.0.1:26657}"

require_cmd curl
require_cmd jq

if [[ -n "${HEALTHCHECK_STATUS:-}" ]]; then
  RESPONSE="$HEALTHCHECK_STATUS"
else
  RESPONSE=$(curl -fsS "$RPC/status" 2>/dev/null || true)
fi

if [[ -z "$RESPONSE" ]]; then
  say "RPC status endpoint unreachable"
  exit 1
fi

CATCHING_UP=$(printf '%s' "$RESPONSE" | jq -r '.result.sync_info.catching_up' 2>/dev/null || echo "true")
if [[ "$CATCHING_UP" == "false" ]]; then
  exit 0
fi

say "Node is still catching up"
exit 1
