#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y docker.io docker-compose git
systemctl enable --now docker

useradd -m -s /bin/bash qubetics || true
usermod -aG docker qubetics

sudo -u qubetics bash <<'SCRIPT'
set -euo pipefail
mkdir -p ~/qubetics-validator
cd ~/qubetics-validator
if [[ ! -d repo ]]; then
  git clone https://github.com/Qubetics/qubetics-validator-starter repo
fi
cd repo
cat > .env <<ENV
DOMAIN=${domain}
ALLOW_IPS=${allow_ips}
DOCKER_TAG=${docker_tag}
PROMETHEUS_PORT=${prometheus_port}
ENV
make setup MONIKER=
SCRIPT
