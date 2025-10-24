#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --network <profile>    Network profile context
  --env-file <path>      Load environment variables from a file
  --help                 Show this message
USAGE
}

if ! parse_common_args "$@"; then
  usage
  exit 0
fi

set -- "${COMMON_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage; exit 0 ;;
    --*)
      die "Unknown flag $1" ;;
    *)
      break ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  die "tune.sh must be run as root"
fi

SYSCTL_FILE="/etc/sysctl.d/99-qubetics.conf"
JOURNALD_FILE="/etc/systemd/journald.conf.d/qubetics.conf"

say "Applying sysctl tuning"
cat <<CFG > "$SYSCTL_FILE"
net.core.somaxconn = 1024
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
fs.file-max = 1048576
vm.swappiness = 10
CFG

sysctl --system >/dev/null 2>&1 || true

say "Configuring journald"
mkdir -p "$(dirname "$JOURNALD_FILE")"
cat <<JCONF > "$JOURNALD_FILE"
[Journal]
Storage=persistent
SystemMaxUse=1G
RuntimeMaxUse=250M
MaxRetentionSec=1month
JCONF

systemctl restart systemd-journald || true

say "Setting ulimits"
LIMITS_FILE="/etc/security/limits.d/qubetics.conf"
cat <<LIMITS > "$LIMITS_FILE"
qubetics soft nofile 65535
qubetics hard nofile 65535
root soft nofile 65535
root hard nofile 65535
LIMITS

say "Tune operation completed"
