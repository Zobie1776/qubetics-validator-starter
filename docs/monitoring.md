# Monitoring Guide

## Metrics stack

- Run `make monitor` for on-demand health snapshots with alerts forwarded to Slack/Discord/Telegram.
- Deploy the Prometheus exporter via `docker-compose.ha.yml` or `make exporter` (ensure the `prometheus-client` Python package is installed).
- Add the exporter target to your Prometheus scrape config:

```yaml
  - job_name: qubetics
    static_configs:
      - targets:
          - validator.example:26660
```

- Import `docs/diagrams/grafana-dashboard.json` into Grafana for a ready-made panel set.

## Alerts

Set environment variables in `.env` to enable push notifications:

- `SLACK_WEBHOOK_URL`
- `DISCORD_WEBHOOK_URL`
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`

Thresholds (`BLOCK_LAG_THRESHOLD`, `PEER_MINIMUM`, etc.) are configurable via `.env`.

## Cron automation

Add entries similar to the following:

```
*/5 * * * * /usr/local/bin/qubetics-monitor >> /var/log/qubetics/monitor.log 2>&1
0 2 * * * cd /opt/qubetics && make snapshot
0 3 * * * cd /opt/qubetics && make backup BACKUP_PASSPHRASE=$PASS
```

Where `/usr/local/bin/qubetics-monitor` contains:

```bash
#!/usr/bin/env bash
cd /opt/qubetics
make monitor RPC=http://127.0.0.1:26657 REFERENCE_RPC=https://rpc.qubetics.org
```

## Grafana dashboard

`docs/diagrams/grafana-dashboard.json` includes panels for block height, peers, CPU/RAM, and alert annotations. Adjust datasource IDs after import.
