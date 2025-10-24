# Changelog

## v1.0.0 - 2024-06-01
### Added
- Comprehensive documentation set (`docs/`) covering deployment, monitoring, security, and FAQs.
- New operational scripts: `monitor.sh`, `backup.sh`, `restore.sh`, `analyze_logs.sh`, `tune.sh`, `benchmark.sh`, and CLI `tools/qubeticsctl.py`.
- Prometheus exporter (`monitoring/exporter.py`) and Grafana dashboard template.
- Docker Compose profiles for single-node and HA deployments plus Terraform/Ansible automation.
- GitHub Actions CI pipeline with linting, tests, security scans, and release automation.
- Pre-commit configuration, CODEOWNERS, ISSUE/PR templates, logrotate config, and `.editorconfig`.

### Changed
- Scripts now honor `.env`, support `--network`, and validate environment variables before performing actions.
- `bootstrap.sh`, `finish.sh`, and `rpc.sh` gained argument parsing, configurable ports, and richer reporting.
- Snapshot workflow split into `snapshot.sh` (create) and `restore.sh` (apply) with retention controls.
- README expanded with architecture diagram, lifecycle flow, monitoring badges, and donation info.

### Fixed
- Harden script now enables auditd with custom rules and reports service status.
- Metrics script and RPC tooling support arbitrary ports and produce structured reports.

## v0.2.0 - 2025-10-23
### Added
- Hardened bootstrap enforcing loopback RPC, systemd overrides, UFW defaults, and fail2ban.
- `scripts/harden.sh` for reusable operating system hardening and reporting.
- RPC tooling with TLS domain connect, NGINX rate limiting, and lockdown modes.
- Operational scripts: `upgrade.sh`, legacy `snapshot.sh`, `metrics.sh`, domain-aware `rpc.sh` updates, and `.reports/` outputs.
- Docker image polish with pinned base images, healthchecks, and compose volume/ulimit tweaks.
- CI workflows (shellcheck, hadolint, CodeQL) plus Dependabot updates.
- Repository policies: MIT license (superseded by Apache-2.0), Code of Conduct, Contributing guide, Security policy.
- Expanded README covering backups, sentry topology, metrics usage, and domain connect workflow.

### Changed
- Finish script resolved denom exponent math and enforced ≥25k TICS.
- Bootstrap script called hardening routines, ensured loopback RPC, and wrote richer reports.

### Fixed
- Healthcheck exited non-zero while the node was catching up.

## v0.1.0 - 2024-01-01
### Added
- Initial bootstrap and finish scripts for Qubetics mainnet validators.
- Basic Dockerfile and compose stack for containerized deployments.
- README documenting bootstrap/finish flow and security considerations.
