#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --duration <seconds>   Duration for CPU benchmark (default 10)
  --network <profile>    Network profile context
  --env-file <path>      Load environment variables from a file
  --help                 Show this message
USAGE
}

DURATION="${BENCHMARK_DURATION:-10}"

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

set -- "${COMMON_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration)
      DURATION="$2"; shift 2 ;;
    --help)
      usage; exit 0 ;;
    --*)
      die "Unknown flag $1" ;;
    *)
      break ;;
  esac
done

require_cmd openssl

say "Running CPU benchmark for $DURATION seconds"
CPU_OUTPUT="$(openssl speed -seconds "$DURATION" sha256 2>/dev/null | tail -n 1 || echo '')"

say "Running disk throughput test"
TEMP_FILE="$(mktemp /tmp/qubetics-bench.XXXXXX)"
trap 'rm -f "$TEMP_FILE"' EXIT
DISK_OUTPUT=$(dd if=/dev/zero of="$TEMP_FILE" bs=1M count=512 conv=fdatasync 2>&1 | tail -n 1)

REPORT_FILE="${REPORTS_DIR}/benchmark.md"
cat <<REPORT > "$REPORT_FILE"
# Hardware Benchmark

- Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Duration: ${DURATION}s

## CPU (openssl speed sha256)
$CPU_OUTPUT

## Disk (dd 512MB)
$DISK_OUTPUT
REPORT

say "Benchmark written to $REPORT_FILE"
