#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

KEY_NAME="${KEY_NAME:-validator}"
HOME_DIR="${HOME_DIR:-/data/.tmp-qubeticsd}"
RPC="${RPC:-http://127.0.0.1:26657}"
MIN_TICS="${MIN_TICS:-25000}"
MONIKER_DEFAULT="${MONIKER:-Q-Sync}"
NODE_HOME="${NODE_HOME:-/data/.qubeticsd}"
REPORT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/.reports"
REPORT_FILE="$REPORT_DIR/finish.md"

mkdir -p "$REPORT_DIR" "$HOME_DIR"

require_cmd qubeticsd
require_cmd jq
require_cmd curl
require_cmd python3

say "Starting validator finish phase"

KEY_HOME="$HOME_DIR"
KEYRING_FLAGS=(--keyring-backend file --home "$KEY_HOME")
if ! qubeticsd keys show "$KEY_NAME" "${KEYRING_FLAGS[@]}" >/dev/null 2>&1; then
  DEFAULT_KEY_HOME="${HOME}/.qubeticsd"
  if qubeticsd keys show "$KEY_NAME" --keyring-backend file --home "$DEFAULT_KEY_HOME" >/dev/null 2>&1; then
    KEY_HOME="$DEFAULT_KEY_HOME"
    KEYRING_FLAGS=(--keyring-backend file --home "$KEY_HOME")
    say "Using keyring at $KEY_HOME"
  else
    die "Key '$KEY_NAME' not found. Import it with: qubeticsd keys add $KEY_NAME --recover --keyring-backend file"
  fi
fi

ADDRESS=$(qubeticsd keys show "$KEY_NAME" "${KEYRING_FLAGS[@]}" --address)
say "Validator wallet address: $ADDRESS"

STATUS_JSON=$(curl -sf "$RPC/status") || die "Unable to query node status from $RPC"
CHAIN_ID=$(echo "$STATUS_JSON" | jq -r '.result.node_info.network')
CATCHING_UP=$(echo "$STATUS_JSON" | jq -r '.result.sync_info.catching_up')

if [[ "$CHAIN_ID" == "null" || -z "$CHAIN_ID" ]]; then
  die "Unable to determine chain-id from RPC"
fi

say "Detected chain-id: $CHAIN_ID"

if [[ "$CATCHING_UP" != "false" ]]; then
  die "Node is still catching up. Wait until sync completes before creating the validator"
fi

STAKING_PARAMS=$(qubeticsd q staking params --node "$RPC" -o json)
BOND_DENOM=$(echo "$STAKING_PARAMS" | jq -r '.params.bond_denom // .bond_denom')

if [[ "$BOND_DENOM" == "null" || -z "$BOND_DENOM" ]]; then
  die "Unable to determine staking denom"
fi

METADATA=$(qubeticsd q bank denom-metadata --node "$RPC" -o json)
DENOM_EXPONENT=$(echo "$METADATA" | jq --arg denom "$BOND_DENOM" -r '.metadatas[] | select(.base==$denom).denom_units[] | select(.denom==$denom).exponent' | head -n1)
if [[ -z "$DENOM_EXPONENT" || "$DENOM_EXPONENT" == "null" ]]; then
  DENOM_EXPONENT=0
fi

say "Bond denom: $BOND_DENOM (exponent: $DENOM_EXPONENT)"

BALANCES=$(qubeticsd q bank balances "$ADDRESS" --node "$RPC" -o json)
BALANCE_BASE=$(echo "$BALANCES" | jq --arg denom "$BOND_DENOM" -r '.balances[] | select(.denom==$denom).amount' | head -n1)
BALANCE_BASE=${BALANCE_BASE:-0}

REQUIRED_BASE=$(python3 - <<PY
from decimal import Decimal
print(int(Decimal("$MIN_TICS") * (Decimal(10) ** Decimal($DENOM_EXPONENT))))
PY
)

if (( BALANCE_BASE < REQUIRED_BASE )); then
  die "Insufficient balance. Need at least ${MIN_TICS} ${BOND_DENOM}, have $BALANCE_BASE base units"
fi

say "Balance requirement satisfied"

read -r -p "Moniker [$MONIKER_DEFAULT]: " INPUT_MONIKER
MONIKER_VALUE="${INPUT_MONIKER:-$MONIKER_DEFAULT}"
read -r -p "Commission rate (e.g. 0.10) [0.10]: " COMMISSION_RATE
COMMISSION_RATE="${COMMISSION_RATE:-0.10}"
read -r -p "Commission max rate [0.20]: " COMMISSION_MAX
COMMISSION_MAX="${COMMISSION_MAX:-0.20}"
read -r -p "Commission max change rate [0.01]: " COMMISSION_CHANGE
COMMISSION_CHANGE="${COMMISSION_CHANGE:-0.01}"
read -r -p "Self delegation amount (${BOND_DENOM}) [$MIN_TICS]: " SELF_DELEG_TOKENS
SELF_DELEG_TOKENS="${SELF_DELEG_TOKENS:-$MIN_TICS}"

SELF_DELEG_BASE=$(python3 - <<PY
from decimal import Decimal
print(int(Decimal("$SELF_DELEG_TOKENS") * (Decimal(10) ** Decimal($DENOM_EXPONENT))))
PY
)

if (( SELF_DELEG_BASE <= 0 )); then
  die "Self delegation must be greater than zero"
fi

if (( SELF_DELEG_BASE < REQUIRED_BASE )); then
  die "Self delegation must be at least ${MIN_TICS} ${BOND_DENOM}"
fi

PUBKEY=$(qubeticsd tendermint show-validator --home "$NODE_HOME" 2>/dev/null || true)
if [[ -z "$PUBKEY" ]]; then
  die "Unable to read validator pubkey from $NODE_HOME"
fi

say "Preparing create-validator transaction"
confirm "Broadcast create-validator transaction now? [y/N]" || die "Validator creation aborted"

qubeticsd tx staking create-validator \
  --amount "${SELF_DELEG_BASE}${BOND_DENOM}" \
  --pubkey "$PUBKEY" \
  --moniker "$MONIKER_VALUE" \
  --chain-id "$CHAIN_ID" \
  --commission-rate "$COMMISSION_RATE" \
  --commission-max-rate "$COMMISSION_MAX" \
  --commission-max-change-rate "$COMMISSION_CHANGE" \
  --min-self-delegation "$SELF_DELEG_BASE" \
  --from "$KEY_NAME" \
  --node "$RPC" \
  --gas auto --gas-adjustment 1.2 \
  --keyring-backend file \
  --home "$KEY_HOME" \
  --yes

say "Transaction submitted. Waiting for node to confirm validator creation"

for attempt in {1..60}; do
  sleep 10
  STATUS_JSON=$(curl -sf "$RPC/status") || continue
  CATCHING_UP=$(echo "$STATUS_JSON" | jq -r '.result.sync_info.catching_up')
  if [[ "$CATCHING_UP" == "false" ]]; then
    break
  fi
  say "... waiting for node sync (attempt $attempt)"
done

say "Validator creation flow complete"

cat <<MARKDOWN > "$REPORT_FILE"
# Finish Report

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Chain ID: $CHAIN_ID
- Moniker: $MONIKER_VALUE
- Wallet: $ADDRESS
- Self Delegation: $SELF_DELEG_TOKENS $BOND_DENOM
MARKDOWN

say "Report written to $REPORT_FILE"
