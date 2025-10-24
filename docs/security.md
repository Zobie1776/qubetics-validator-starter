# Security Guide

Security breaches result in slashing, downtime, or loss of operator reputation. Follow the checklist below for defense-in-depth.

## OS hardening

- Run `make setup` to apply systemd sandboxing, UFW defaults, fail2ban, and auditd watch rules.
- Disable password authentication: edit `/etc/ssh/sshd_config` and set `PasswordAuthentication no`, then `systemctl reload sshd`.
- Keep the base OS patched (`unattended-upgrades` or weekly maintenance windows).

## Access control

- Restrict SSH access via `AllowUsers` or IP allow-lists.
- Use hardware tokens or FIDO2 keys for sudo escalation.
- Maintain a privileged access management (PAM) log and rotate credentials quarterly.

## Validator keys

- Store mnemonic offline; the server should only hold `priv_validator_key.json` and `priv_validator_state.json`.
- Take encrypted backups using `make backup BACKUP_PASSPHRASE=...` and store them in offline vaults.
- Before upgrades, ensure snapshots and backups have been validated on staging hosts.

## Slashing protection

- Never run two validators with the same keys simultaneously.
- When migrating, stop the old node, run `make backup`, restore onto the new node with `make snapshot-restore`, then start the new validator.
- Monitor `priv_validator_state.json` timestamps to confirm only one signer instance is active.

## Incident response

1. Trigger `make monitor` from a bastion to collect metrics.
2. Lock down RPC using `make rpc-lockdown`.
3. Use `scripts/analyze_logs.sh` to extract anomalies.
4. Engage the security mailing list and prepare disclosure statements.

## Audit tooling

- `scripts/harden.sh` installs auditd rules watching validator config directories.
- For centralized logging, forward `/var/log/qubetics` using rsyslog or Elastic agents.
- Periodically review `docs/monitoring.md` for KPI thresholds.
