#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --network <profile>    Network profile (mainnet/testnet)
  --rpc <url>            Tendermint RPC endpoint (default http://127.0.0.1:${RPC_PORT})
  --chain-id <id>        Override detected chain-id
  --min-tics <amount>    Minimum self delegation in display units
  --moniker <name>       Moniker override
  --home <path>          Qubetics home directory
  --non-interactive      Skip prompts and confirmations (requires env values)
  --env-file <path>      Load variables from custom env file
  --help                 Show this help
USAGE
}

HOME_DIR="${HOME_DIR:-/data/.tmp-qubeticsd}"
KEY_NAME="${KEY_NAME:-validator}"
RPC="${RPC:-http://127.0.0.1:${RPC_PORT}}"
MIN_TICS="${MIN_TICS:-25000}"
MONIKER_DEFAULT="${MONIKER:-NovaOS-1}"
NON_INTERACTIVE=false

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

set -- "${COMMON_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc)
      RPC="$2"; shift 2 ;;
    --chain-id)
      CHAIN_ID="$2"; shift 2 ;;
    --min-tics)
      MIN_TICS="$2"; shift 2 ;;
    --moniker)
      MONIKER_DEFAULT="$2"; shift 2 ;;
    --home)
      HOME_DIR="$2"; shift 2 ;;
    --non-interactive)
      NON_INTERACTIVE=true; shift ;;
    --help)
      usage; exit 0 ;;
    --*)
      die "Unknown flag $1" ;;
    *)
      break ;;
  esac
done

mkdir -p "$REPORTS_DIR" "$HOME_DIR"

require_cmd qubeticsd
require_cmd jq
require_cmd curl
require_cmd python3
require_env MIN_TICS

say "Starting validator finish phase"

KEYRING_FLAGS=(--keyring-backend "${KEYRING_BACKEND:-file}" --home "$HOME_DIR")
if ! qubeticsd keys show "$KEY_NAME" "${KEYRING_FLAGS[@]}" >/dev/null 2>&1; then
  say "Key '$KEY_NAME' not found in $HOME_DIR."
  say "Import it with: qubeticsd keys add $KEY_NAME --recover --keyring-backend file --home \"$HOME_DIR\""
  exit 1
fi

ADDRESS=$(qubeticsd keys show "$KEY_NAME" "${KEYRING_FLAGS[@]}" --address)
STATUS_JSON="$(curl -fsS "$RPC/status" 2>/dev/null || qubeticsd status --node "$RPC" 2>/dev/null || echo '{}')"
CHAIN_ID_AUTO="$(printf '%s' "$STATUS_JSON" | json '.result.node_info.network' 2>/dev/null || echo '')"
CATCHING_UP="$(printf '%s' "$STATUS_JSON" | json '.result.sync_info.catching_up' 2>/dev/null || echo '')"
if [[ -z "${CHAIN_ID:-}" || "${CHAIN_ID}" == "null" ]]; then
  CHAIN_ID="$CHAIN_ID_AUTO"
fi

if [[ -z "$CHAIN_ID" || "$CHAIN_ID" == "null" ]]; then
  die "Unable to determine chain-id from $RPC"
fi

STAKING_PARAMS="$(qubeticsd q staking params --node "$RPC" -o json 2>/dev/null || echo '{}')"
DENOM="$(printf '%s' "$STAKING_PARAMS" | json '.params.bond_denom // .bond_denom' 2>/dev/null || echo '')"
if [[ -z "$DENOM" || "$DENOM" == "null" ]]; then
  die "Unable to determine staking denom"
fi

DENOM_METADATA="$(qubeticsd q bank denom-metadata --node "$RPC" -o json 2>/dev/null || echo '{}')"
EXPONENT="$(printf '%s' "$DENOM_METADATA" | jq --arg denom "$DENOM" -r '.metadatas[]? | select(.base==$denom).denom_units[]? | select(.denom==$denom).exponent' | head -n1)"
if [[ -z "$EXPONENT" || "$EXPONENT" == "null" ]]; then
  say "Warning: unable to determine exponent for $DENOM. Defaulting to 6"
  EXPONENT=6
fi

MIN_BASE=$(python3 - <<PY
from decimal import Decimal
print(int(Decimal("$MIN_TICS") * (Decimal(10) ** Decimal($EXPONENT))))
PY
)

BALANCES="$(qubeticsd q bank balances "$ADDRESS" --node "$RPC" -o json 2>/dev/null || echo '{}')"
BALANCE_BASE="$(printf '%s' "$BALANCES" | jq --arg denom "$DENOM" -r '.balances[]? | select(.denom==$denom).amount' | head -n1)"
BALANCE_BASE="${BALANCE_BASE:-0}"

say "Detected chain: $CHAIN_ID"
say "Bond denom: $DENOM (exp=$EXPONENT)"
say "Wallet balance: ${BALANCE_BASE}${DENOM}"

MONIKER_VALUE="$MONIKER_DEFAULT"
SELF_TICS="$MIN_TICS"
COMMISSION_RATE="${COMMISSION_RATE:-0.10}"
COMMISSION_MAX="${COMMISSION_MAX:-0.20}"
COMMISSION_CHANGE="${COMMISSION_CHANGE:-0.01}"

if ! $NON_INTERACTIVE; then
  read -r -p "Moniker [$MONIKER_VALUE]: " INPUT_MONIKER
  MONIKER_VALUE="${INPUT_MONIKER:-$MONIKER_VALUE}"
  while [[ -z "$MONIKER_VALUE" ]]; do
    read -r -p "Moniker cannot be empty. Moniker [$MONIKER_DEFAULT]: " INPUT_MONIKER
    MONIKER_VALUE="${INPUT_MONIKER:-$MONIKER_DEFAULT}"
  done

  read -r -p "Commission rate (e.g. 0.10) [$COMMISSION_RATE]: " INPUT_RATE
  COMMISSION_RATE="${INPUT_RATE:-$COMMISSION_RATE}"
  read -r -p "Commission max rate [$COMMISSION_MAX]: " INPUT_MAX
  COMMISSION_MAX="${INPUT_MAX:-$COMMISSION_MAX}"
  read -r -p "Commission max change rate [$COMMISSION_CHANGE]: " INPUT_CHANGE
  COMMISSION_CHANGE="${INPUT_CHANGE:-$COMMISSION_CHANGE}"
  read -r -p "Self delegation amount (TICS) [$SELF_TICS]: " INPUT_SELF
  SELF_TICS="${INPUT_SELF:-$SELF_TICS}"
fi

SELF_BASE=$(python3 - <<PY
from decimal import Decimal
print(int(Decimal("$SELF_TICS") * (Decimal(10) ** Decimal($EXPONENT))))
PY
)

if [[ "$SELF_BASE" -lt "$MIN_BASE" ]]; then
  die "Self delegation must be at least ${MIN_TICS} TICS"
fi

if [[ "$BALANCE_BASE" -lt "$SELF_BASE" ]]; then
  die "Insufficient balance for self delegation"
fi

PUBKEY=$(qubeticsd tendermint show-validator --home "$HOME_DIR" 2>/dev/null || echo '')
if [[ -z "$PUBKEY" ]]; then
  die "Unable to read validator pubkey from $HOME_DIR"
fi

say "--- Dry Run Summary ---"
say "Chain: ${CHAIN_ID}"
say "Denom/base: ${DENOM} (exp=${EXPONENT})"
say "You will self-delegate: ${SELF_TICS} TICS == ${SELF_BASE}${DENOM}"
say "min_self_delegation: ${MIN_BASE}${DENOM}"

if ! $NON_INTERACTIVE; then
  if ! confirm "Confirm create-validator transaction? (y/N)"; then
    exit 1
  fi
fi

qubeticsd tx staking create-validator \
  --amount "${SELF_BASE}${DENOM}" \
  --pubkey "$PUBKEY" \
  --moniker "$MONIKER_VALUE" \
  --chain-id "$CHAIN_ID" \
  --commission-rate "$COMMISSION_RATE" \
  --commission-max-rate "$COMMISSION_MAX" \
  --commission-max-change-rate "$COMMISSION_CHANGE" \
  --min-self-delegation "$MIN_BASE" \
  --from "$KEY_NAME" \
  --node "$RPC" \
  --gas auto --gas-adjustment 1.2 \
  --keyring-backend "${KEYRING_BACKEND:-file}" \
  --home "$HOME_DIR" \
  --yes

say "Transaction broadcast. Monitoring sync status"

for attempt in $(seq 1 90); do
  sleep 10
  STATUS_JSON="$(curl -fsS "$RPC/status" 2>/dev/null || echo '{}')"
  CATCHING_UP="$(printf '%s' "$STATUS_JSON" | json '.result.sync_info.catching_up' 2>/dev/null || echo '')"
  say "Status check #$attempt catching_up=$CATCHING_UP"
  if [[ "$CATCHING_UP" == "false" ]]; then
    break
  fi
  if [[ $attempt -eq 90 ]]; then
    say "Warning: node still catching up after validation wait"
  fi
done

REPORT_FILE="${REPORTS_DIR}/finish.md"
cat <<MARKDOWN > "$REPORT_FILE"
# Finish Report

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Chain: $CHAIN_ID
- Address: $ADDRESS
- Moniker: $MONIKER_VALUE
- Self Delegation: ${SELF_TICS} TICS (${SELF_BASE}${DENOM})
- Min Self Delegation: ${MIN_BASE}${DENOM}
MARKDOWN

say "Finish phase summary written to $REPORT_FILE"
