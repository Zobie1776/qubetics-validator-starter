# Contributing Guidelines

Thank you for your interest in improving the Qubetics Validator Starter.

## Getting started

1. Fork the repository and create a feature branch from `main`.
2. Install required tooling (`shellcheck`, `hadolint`, `jq`, `curl`).
3. Copy `.env.example` to `.env` and adjust values for local testing if needed.

## Development workflow

- Follow the provided Make targets. Useful commands:
  - `make setup` – bootstrap and harden a node (requires root privileges).
  - `make metrics` – quick sanity check that the node is reachable.
  - `make docker-up` / `make docker-down` – containerised testing.
- All shell scripts must begin with `#!/usr/bin/env bash`, `set -Eeuo pipefail`, and source `scripts/utils.sh` for shared helpers.
- Scripts should remain idempotent; re-running them must not duplicate config or break state.
- Logs and human-readable reports belong in `.reports/` (see existing scripts for examples).

## Coding style

- Run `shellcheck scripts/*.sh` and `hadolint docker/Dockerfile` before submitting a pull request.
- Prefer POSIX-compliant bash; avoid Bashisms that shellcheck flags unless justified.
- Never store or print sensitive material (mnemonics, private keys, passwords).
- When editing configs, use anchored `sed`/`awk` updates or rewrite entire files to keep re-runs safe.

## Commit messages

We follow [Conventional Commits](https://www.conventionalcommits.org/). Example scopes:

- `feat(rpc): add domain connect helper`
- `fix(bootstrap): guard against missing config`
- `docs(readme): expand metrics section`

## Pull requests

- Link related issues in the PR description.
- Include a summary of manual testing (commands, logs).
- Ensure CI passes (shellcheck, hadolint, CodeQL, workflows).
- Be responsive to review feedback—small, focused commits are easier to review.

## Security disclosures

Report suspected security issues privately to [security@qubetics.org](mailto:security@qubetics.org). Do **not** open a public issue for vulnerabilities.

We appreciate your contributions!
