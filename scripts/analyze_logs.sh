#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --service <name>   Systemd service name (default qubeticschain.service)
  --since <period>   Journalctl since filter (default 6 hours)
  --env-file <path>  Load variables from a file
  --help             Show this help message
USAGE
}

SERVICE_NAME="${SERVICE_NAME:-qubeticschain.service}"
SINCE="${SINCE:-6 hours ago}"

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

set -- "${COMMON_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)
      SERVICE_NAME="$2"; shift 2 ;;
    --since)
      SINCE="$2"; shift 2 ;;
    --help)
      usage; exit 0 ;;
    --*)
      die "Unknown flag $1" ;;
    *)
      break ;;
  esac
done

require_cmd journalctl

say "Analyzing logs for $SERVICE_NAME since '$SINCE'"
LOG_OUTPUT="$(journalctl -u "$SERVICE_NAME" --since "$SINCE" --no-pager 2>/dev/null || echo '')"
if [[ -z "$LOG_OUTPUT" ]]; then
  die "No logs retrieved"
fi

ANOMALIES=$(printf '%s\n' "$LOG_OUTPUT" | grep -Ei 'panic|error|failed|slashing|double sign|consensus failure|peer drop' || true)
PEER_DROPS=$(printf '%s\n' "$LOG_OUTPUT" | grep -E 'dialing|too many peers|connection refused' | wc -l | tr -d ' ')
RESTARTS=$(printf '%s\n' "$LOG_OUTPUT" | grep -E 'Starting service|qubeticsd start' | wc -l | tr -d ' ')

REPORT_FILE="${REPORTS_DIR}/log-analysis.md"
cat <<REPORT > "$REPORT_FILE"
# Log Analysis

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Service: $SERVICE_NAME
- Window: $SINCE
- Restarts detected: $RESTARTS
- Peer drop indicators: $PEER_DROPS

## Critical entries

```
${ANOMALIES:-None detected}
```
REPORT

say "Log analysis written to $REPORT_FILE"
