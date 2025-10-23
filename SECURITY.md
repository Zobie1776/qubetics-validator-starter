# Security Policy

## Supported versions

The `main` branch is actively maintained. Security fixes will be applied to the most recent tagged release.

## Reporting a vulnerability

1. Email [security@qubetics.org](mailto:security@qubetics.org) with a detailed description of the vulnerability.
2. Include reproduction steps, affected components (scripts, Docker image, workflows), and potential impact.
3. Allow up to 3 business days for acknowledgement. We will coordinate on remediation timelines and disclosure once a fix is available.

Please do not open public issues or discuss vulnerabilities in community channels until a coordinated disclosure has been agreed.

## Hardening recommendations

- Keep validator hosts patched and rebooted promptly after kernel or glibc updates.
- Restrict SSH access with strong authentication (preferably hardware-backed) and unique users.
- Monitor `.reports/` outputs for unexpected changes. Investigate immediately if RPC laddr deviates from `127.0.0.1`.
- Use the provided `make snapshot` and `make upgrade` scripts to maintain safe backups prior to major operations.

Thank you for helping keep the network secure.
