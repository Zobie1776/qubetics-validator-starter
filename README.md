# Q-Sync Qubetics Validator Starter

Production-ready automation scripts and container tooling for bootstrapping and operating a Qubetics Mainnet validator. The workflow is split into two guarded phases so you can harden the server, import keys offline, and review state before submitting any transactions.

## Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Backups](#backups)
- [Sentry topology](#sentry-topology)
- [Phase 1: Bootstrap](#phase-1-bootstrap)
- [Manual wallet import](#manual-wallet-import)
- [Phase 2: Finish](#phase-2-finish)
- [RPC exposure controls](#rpc-exposure-controls)
  - [Domain connect](#domain-connect)
- [Metrics](#metrics)
- [Upgrade and snapshot workflow](#upgrade-and-snapshot-workflow)
- [Docker workflow](#docker-workflow)
- [Continuous integration](#continuous-integration)
- [Troubleshooting](#troubleshooting)

## Features

- Hardened bootstrap that installs dependencies, applies systemd sandboxing, configures UFW + fail2ban, and locks RPC to localhost.
- Explicit pause for manual key recovery. Mnemonics are **never** printed or stored by any script.
- Finish phase that validates staking metadata (denom, exponent, chain ID) and enforces ≥25,000 TICS self delegation before broadcasting a `create-validator` transaction.
- RPC management helpers to keep Tendermint on loopback, expose behind a rate-limited TLS proxy with IP allow-lists, or instantly lock back down.
- Operational scripts for upgrades, snapshot restoration, metrics inspection, health checks, and hardened report logging in `.reports/`.
- Docker image + compose stack with pinned base images, runtime healthcheck, and peer-only networking.
- CI workflows (shellcheck, hadolint, CodeQL, Dependabot) enforcing code hygiene and dependency freshness.

## Prerequisites

- Ubuntu 20.04/22.04 LTS server with root access.
- 25,000+ TICS available in the validator wallet for self-delegation.
- DNS `A/AAAA` records pointing to the server if you plan to enable TLS RPC access.
- Valid email address for Let’s Encrypt registration when using domain connect.

## Quick start

```bash
# Phase 1 – bootstrap the node (installs dependencies, hardens the OS)
make setup MONIKER=NovaOS-1

# Recover validator key OFFLINE, on a secure machine, then import it here
qubeticsd keys add validator --recover --keyring-backend file --home /data/.tmp-qubeticsd

# Phase 2 – finish once the node is fully synced and funded
make finish

# Keep RPC locked down to localhost (default)
make rpc-local

# Optional: publish a TLS RPC endpoint protected by IP allow-listing
make rpc-domain DOMAIN=rpc.example.com ALLOW_IPS=1.2.3.4,5.6.7.8 EMAIL=you@example.com

# Revoke exposure and return to localhost-only mode
make rpc-lockdown

# Inspect node height, peer count, and sync status anytime
make metrics
```

All scripts emit run logs and Markdown summaries under `.reports/` for auditability.

## Backups

Always maintain secure copies of the following files before any upgrade or migration:

- `/data/.tmp-qubeticsd/config/priv_validator_key.json`
- `/data/.tmp-qubeticsd/config/priv_validator_state.json`
- `/data/.tmp-qubeticsd/config/node_key.json`
- `/data/.tmp-qubeticsd/config/*` (genesis, app.toml, config.toml, client.toml)

Example archive command:

```bash
sudo tar -czvf $HOME/qubetics-backup-$(date -u +%Y%m%d).tar.gz \
  /data/.tmp-qubeticsd/config/priv_validator_key.json \
  /data/.tmp-qubeticsd/config/priv_validator_state.json \
  /data/.tmp-qubeticsd/config/node_key.json \
  /data/.tmp-qubeticsd/config
```

Store backups offline (encrypted) and verify integrity before destructive operations.

## Sentry topology

Operate validators behind sentry nodes to isolate the signing key from the public Internet:

1. Keep the validator on a private network with RPC bound to `127.0.0.1` only.
2. Run one or more public sentry nodes that peer with other validators and expose port `26656`.
3. Establish private persistent peers between validator ↔ sentries.
4. Never expose validator RPC ports (`26657`) directly; use sentry RPCs or the TLS proxy from a hardened bastion.

This starter focuses on the validator host. Combine it with separate sentry infrastructure for production deployments.

## Phase 1: Bootstrap

`scripts/bootstrap.sh` performs the initial system hardening and node installation. Actions include:

1. Ensures `/data` exists for validator state and creates `WORKDIR` (default `$HOME/nodes/qubetics`).
2. Installs dependencies: `git`, `curl`, `jq`, `ufw`, `fail2ban`, `build-essential`, `unzip`, `lz4`, `nginx`, `certbot`.
3. Applies `scripts/harden.sh` for systemd sandboxing, UFW defaults (deny inbound except SSH/26656), and fail2ban SSH jail.
4. Clones the official [`qubetics-mainnetnode-script`](https://github.com/Qubetics/qubetics-mainnetnode-script) repository, preferring the fast-sync installer when present.
5. Registers a hardened `qubeticschain.service` systemd unit and waits for the local RPC endpoint to respond.
6. Writes `.reports/bootstrap.md` with node metadata, sync status, and firewall summary.

Re-run the bootstrap script safely—it's idempotent and refreshes upstream installers when available.

## Manual wallet import

After bootstrap, **stop** and import your validator key manually:

```bash
qubeticsd keys add validator --recover --keyring-backend file --home /data/.tmp-qubeticsd
```

Perform the mnemonic recovery offline and transfer the resulting key files securely. The scripts never request or log private material.

## Phase 2: Finish

`scripts/finish.sh` validates the environment and submits the validator creation transaction.

- Detects chain ID, staking denom, and exponent directly from the node.
- Verifies the configured key exists (default `KEY_NAME=validator`). If missing, the script prints explicit recovery instructions.
- Computes base-unit math so ≥25,000 TICS are self-delegated, with warnings when balances are insufficient.
- Prompts for moniker, commission parameters, and self-delegation, then presents a dry-run summary before confirming.
- Broadcasts `tx staking create-validator` with gas auto/adjustment 1.2 and monitors sync until `catching_up=false`.
- Writes `.reports/finish.md` containing chain metadata, delegation amounts, and validation status.

## RPC exposure controls

`scripts/rpc.sh` centralizes RPC hardening.

- `make rpc-local` – binds Tendermint RPC to `127.0.0.1`, restarts the service, deletes any NGINX proxy, and denies 26657 via UFW.
- `make rpc-expose` – creates a local HTTPS proxy using the Debian snake-oil certificate, rate limits to 5r/s, and keeps all clients denied by default (for testing).
- `make rpc-lockdown` – removes enabled proxy sites, closes port 443, and re-applies loopback bindings.
- `make status` – inspects bindings, firewall rules, catching-up state, and proxy status, emitting a Markdown report.

### Domain connect

Enable a production TLS endpoint with IP allow-listing and automatic Let’s Encrypt certificates:

```bash
make rpc-domain DOMAIN=rpc.example.com ALLOW_IPS=1.2.3.4,5.6.7.8 EMAIL=you@domain.tld
```

What it does:

1. Confirms DNS resolves to your server’s public IP (warns if not).
2. Installs NGINX + Certbot, obtains/renews certificates via `certbot --nginx`.
3. Writes `/etc/nginx/sites-available/qubetics-rpc` to proxy `/rpc/` → `http://127.0.0.1:26657/` with rate limits, websocket headers, and allow/deny directives derived from `ALLOW_IPS`.
4. Enables the site, reloads NGINX, and opens port 443 in UFW.
5. Documents the setup in `.reports/domain_connect.md` (DNS, certificates, allow-list).

Roll back exposure at any time:

```bash
make rpc-lockdown
```

## Metrics

`make metrics` runs `scripts/metrics.sh` to display the latest block height, catching-up flag, and peer count from the local RPC endpoint. The command also writes `.reports/metrics.md` with:

- Timestamped snapshot of the current state
- Guidance for enabling Prometheus telemetry in `app.toml`
- Tips for allowing trusted scrapers (port 26660) and building Grafana dashboards

To enable telemetry permanently, edit `/data/.tmp-qubeticsd/config/app.toml`:

- Set `[telemetry].prometheus = true`
- Adjust `prometheus_listen_addr = "0.0.0.0:26660"` if exposing to sentry nodes
- Update UFW or sentry firewalls to allow only trusted Prometheus endpoints

## Upgrade and snapshot workflow

Operational scripts are idempotent and emit reports under `.reports/`:

- `make upgrade VERSION=vX.Y.Z` – stops the validator, archives `/data/config` + key files to `~/.backups/qubetics/`, optionally rebuilds `qubeticsd` from source at `VERSION` (if Go toolchain is installed), restarts the service, and records the new version/height in `.reports/upgrade.md`.
- `make snapshot SNAP_URL=https://snapshot.tar.lz4` – stops the service, backs up keys/config, wipes data directories, restores the provided LZ4 snapshot, tails logs, waits until `catching_up=false`, and documents the recovery in `.reports/snapshot.md`.

Always verify backups before running these commands in production.

## Docker workflow

Build-and-run steps for local testing:

```bash
make docker-up    # build image and launch validator container (P2P port 26656 only)
make docker-logs  # follow container logs
make docker-down  # stop and remove the stack
```

The Docker image compiles `qubeticsd` from a pinned Go toolchain and runtime base, copies the project healthcheck scripts, and exposes only port `26656`. The compose stack mounts a named volume (`qubetics-data`), sets `nofile` ulimits to 65,535, and delegates health monitoring to `scripts/healthcheck.sh`.

## Continuous integration

Two GitHub Actions workflows back the repository:

- `ci.yml` installs shellcheck + hadolint, lints every script and the Dockerfile, runs `make metrics` for a sanity check, and verifies core Make targets exist.
- `codeql.yml` enables CodeQL scanning for Bash and Docker query packs on pushes, pull requests, and a weekly cron schedule.

Dependabot (`.github/dependabot.yml`) checks GitHub Actions and Docker dependencies weekly.

## Troubleshooting

- **RPC unreachable** – Run `make status` to confirm the laddr is `tcp://127.0.0.1:26657` and firewall rules block 26657. Use `make rpc-local` to re-apply loopback defaults.
- **Node still catching up** – Allow more time for block sync. Monitor progress with `journalctl -u qubeticschain.service -f` or container logs.
- **Insufficient balance** – Fund the validator address, then rerun `make finish`. The script will recompute denom/exponent math automatically.
- **TLS issuance failed** – Ensure DNS records point at the server and rerun `make rpc-domain`. The script writes diagnostics to `.reports/domain_connect.md`.

## Next steps

```bash
make setup MONIKER=NovaOS-1
# Import validator key securely (offline)
make finish
make rpc-local
# Optional RPC exposure via domain connect
make rpc-domain DOMAIN=rpc.example.com ALLOW_IPS=1.2.3.4 EMAIL=you@example.com
```
