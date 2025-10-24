# Contributing Guidelines

Thank you for your interest in improving the Qubetics Validator Starter.

## Getting started

1. Fork the repository and create a feature branch from `main`.
2. Install tooling: `pre-commit`, `bats`, `shellcheck`, `yamllint`, `hadolint`.
3. Copy `config.sample.env` to `.env` and adjust values for local testing.
4. Run `pre-commit install` to enable automatic linting before commits.

## Development workflow

- Prefer the provided Make targets:
  - `make setup` – bootstrap and harden a node (requires root privileges).
  - `make finish` – perform validator creation checks.
  - `make monitor`, `make snapshot`, `make backup` – operational smoke tests.
  - `make docker-up` / `make docker-down` – containerised testing.
- All shell scripts must begin with `#!/usr/bin/env bash`, call `set -Eeuo pipefail`, and source `scripts/utils.sh`.
- Keep scripts idempotent and log to `.reports/`.
- Update documentation alongside code changes (README, docs/ guides, changelog entry).

## Commit messages

We follow [Conventional Commits](https://www.conventionalcommits.org/). Examples:

- `feat(monitor): add slack webhook support`
- `fix(bootstrap): guard systemd override path`
- `docs(readme): add architecture diagram`

## Testing

- Run `pre-commit run --all-files` locally before opening a PR.
- Execute `bats tests` to ensure helper scripts respond to `--help`/usage.
- For behavioural changes touching RPC or monitoring, provide manual verification output in the PR description.

## Pull requests

- Link related issues and describe test coverage.
- Ensure CI (lint, security scan, build) is green.
- Keep diffs focused; large changes may be requested to split.
- Update `CONTRIBUTORS.md` if you'd like recognition.

## Security disclosures

Report suspected security issues privately to [security@qubetics.org](mailto:security@qubetics.org). Do **not** open a public issue for vulnerabilities.

We appreciate your contributions!
