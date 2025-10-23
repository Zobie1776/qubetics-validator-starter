# Q-Sync Qubetics Validator Starter

Production-ready automation scripts and container tooling for bootstrapping and operating a Qubetics Mainnet validator named **Q-Sync**. The workflow is deliberately split into two guarded phases so you can harden the server, import keys offline, and review state before submitting any transactions.

## Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Phase 1: Bootstrap](#phase-1-bootstrap)
- [Manual wallet import](#manual-wallet-import)
- [Phase 2: Finish](#phase-2-finish)
- [RPC exposure controls](#rpc-exposure-controls)
- [Docker workflow](#docker-workflow)
- [Continuous integration](#continuous-integration)
- [Troubleshooting](#troubleshooting)

## Features

- Idempotent bootstrap script that installs hardened defaults, configures firewall + fail2ban, and registers a systemd service for the validator.
- Explicit pause for manual key recovery. Mnemonics are **never** printed or stored by any script.
- Finish script that validates balances, discovers chain metadata, and submits a `create-validator` transaction only after the node is fully synced.
- RPC management helper with safe defaults (localhost only) plus audited exposure via NGINX reverse proxy with IP allow-list and rate limiting.
- Docker image that builds `qubeticsd` from source and a compose file that mounts persistent state without exposing the RPC port.
- Makefile for developer ergonomics, CI for linting/scripts/health checks, and markdown reports describing each phase.

## Prerequisites

- Ubuntu 20.04/22.04 LTS server with root access.
- 25,000+ TICS available in the validator wallet for self-delegation.
- DNS record pointing to the server if you plan to expose the RPC endpoint.
- Valid TLS certificates in `/etc/letsencrypt/live/<domain>/` before enabling RPC exposure.

## Quick start

```bash
# Phase 1 – bootstrap the node (installs dependencies, configures firewall)
make setup MONIKER=Q-Sync

# Recover validator key OFFLINE, on a secure machine, then import it here
qubeticsd keys add validator --recover --keyring-backend file

# Phase 2 – finish once the node is fully synced and funded
make finish

# Keep RPC locked down to localhost (default)
make rpc-local

# Optional: expose RPC behind NGINX with IP allow-list
make rpc-expose DOMAIN=rpc.example.com ALLOW_IPS=1.2.3.4,5.6.7.8

# Revoke exposure and return to localhost-only mode
make rpc-lockdown
```

## Phase 1: Bootstrap

`scripts/bootstrap.sh` performs the initial system hardening and node installation. Actions include:

1. Ensures `/data` exists for validator state and creates `WORKDIR` (default `$HOME/nodes/qubetics`).
2. Installs dependencies: `git`, `curl`, `jq`, `ufw`, `fail2ban`, `build-essential`, `unzip`, `lz4`.
3. Configures UFW (allow `22/tcp`, `26656/tcp`; deny `26657/tcp`) and enables fail2ban.
4. Clones the official [`qubetics-mainnetnode-script`](https://github.com/Qubetics/qubetics-mainnetnode-script) repository, preferring the fast-sync installer when present.
5. Registers a hardened `qubeticschain.service` systemd unit and waits for the local RPC endpoint to respond.
6. Writes `.reports/bootstrap.md` with node metadata and explicit next steps.

Re-run the bootstrap script safely—it's idempotent and will refresh the upstream installer if available.

## Manual wallet import

After bootstrap, **stop** and import your validator key manually:

```bash
qubeticsd keys add validator --recover --keyring-backend file
```

Perform the mnemonic recovery offline and transfer the resulting key files to the server using secure means. The scripts never request or log private material.

## Phase 2: Finish

`scripts/finish.sh` validates the environment and submits the validator creation transaction.

- Detects the chain ID, staking denom, and exponent directly from the node.
- Verifies the configured key exists (default `KEY_NAME=validator`) and prints the operator address.
- Checks for a balance ≥ `MIN_TICS` (default 25,000 TICS) before proceeding.
- Prompts for moniker (default `Q-Sync`), commission parameters, and self-delegation.
- Confirms the node is fully synced (`catching_up=false`) prior to broadcasting.
- Waits for the node to report synced status and writes `.reports/finish.md` with transaction context.

## RPC exposure controls

`scripts/rpc.sh` centralizes RPC hardening:

- `make rpc-local` – binds Tendermint RPC to `127.0.0.1` and closes firewall rules.
- `make rpc-expose DOMAIN=<domain> ALLOW_IPS=ip1,ip2` – installs NGINX, creates an HTTPS reverse proxy on port 443 with IP allow-listing and a `5r/s` rate limit, and updates UFW accordingly. A confirmation prompt prevents accidental exposure.
- `make rpc-lockdown` – removes the proxy, closes port 443, and reverts to localhost-only bindings.
- `make status` – inspects current bindings, firewall rules, and local RPC reachability.

Certificates are expected at `/etc/letsencrypt/live/<domain>/`. The script warns if they are missing.

## Docker workflow

Build-and-run steps are available for local testing:

```bash
make docker-up    # build image and launch validator container (P2P port 26656 only)
make docker-logs  # follow container logs
make docker-down  # stop and remove the stack
```

The Docker image compiles `qubeticsd` from source (override `QUBETICS_TAG` as needed), mounts `/data` for persistence, and includes a healthcheck that mirrors the on-host script.

## Continuous integration

`.github/workflows/ci.yml` enforces:

- `shellcheck` across all shell scripts.
- A dry-run healthcheck script invocation.
- Validation that required Make targets exist.
- GitHub secret scanning to prevent accidental credential leaks.

## Troubleshooting

- **RPC unreachable** – Run `make status` to ensure UFW rules and Tendermint bindings are correct. Use `make rpc-local` to reset to localhost bindings.
- **Node still catching up** – Allow more time for block sync. Monitor progress with `journalctl -u qubeticschain.service -f` or the Docker logs.
- **Insufficient balance** – Fund the validator address and re-run `make finish`.
- **Missing certificates** – Issue TLS certificates before running `make rpc-expose`; otherwise NGINX will fail to start.

## Next steps

```bash
make setup MONIKER=Q-Sync
# Import validator key securely (offline)
make finish
make rpc-local
# Optional RPC exposure:
make rpc-expose DOMAIN=rpc.example.com ALLOW_IPS=1.2.3.4
```
