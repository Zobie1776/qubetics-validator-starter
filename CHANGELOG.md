# Changelog

## v0.2.0 - 2025-10-23

### Added
- Hardened bootstrap that enforces loopback RPC, applies systemd overrides, configures UFW defaults, and installs fail2ban.
- `scripts/harden.sh` for reusable operating system hardening and reporting.
- RPC tooling with TLS domain connect, NGINX rate limiting, and lockdown modes.
- Operational scripts: `upgrade.sh`, `snapshot.sh`, `metrics.sh`, domain-aware `rpc.sh` updates, and `.reports/` outputs.
- Docker image polish with pinned base images, healthchecks, and compose volume/ulimit tweaks.
- CI workflows (shellcheck, hadolint, CodeQL) plus Dependabot updates for GitHub Actions and Docker.
- Repository policies: MIT license, Code of Conduct, Contributing guide, and Security policy.
- Expanded README covering backups, sentry topology, metrics usage, and domain connect workflow.

### Changed
- Finish script now resolves denom exponent math, enforces ≥25k TICS, and provides a dry-run summary before broadcasting.
- Bootstrap script calls hardening routines, ensures loopback RPC, and writes richer reports.

### Fixed
- Healthcheck exits non-zero while the node is still catching up.
