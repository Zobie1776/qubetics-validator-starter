# Frequently Asked Questions

## How do I change the minimum self delegation?
Set `MIN_TICS` in `.env` or pass `--min-tics` to `scripts/finish.sh`. The script enforces the threshold before broadcasting.

## Can I run multiple validators with the same keys?
No. Doing so risks double-signing and slashing. Follow the migration procedure in `docs/security.md`.

## Where are reports stored?
All operational scripts drop Markdown/JSON reports into `.reports/` for auditing.

## How do I reset the node?
1. Stop the systemd service.
2. Run `make snapshot-restore SNAP_URL=<trusted snapshot>` or resync from genesis.
3. Verify height with `tools/qubeticsctl.py status`.

## What if the exporter fails to start?
Ensure `prometheus-client` Python package is installed. The Compose HA stack installs it automatically; for manual usage run `pip install prometheus-client`.

## Can I add custom alerts?
Yes. Extend `scripts/monitor.sh` or hook into the exported Prometheus metrics using Alertmanager rules.
