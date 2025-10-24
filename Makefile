SHELL := /bin/bash

.PHONY: setup finish status logs rpc-local rpc-expose rpc-lockdown rpc-domain upgrade snapshot snapshot-restore backup monitor analyze-logs tune benchmark metrics docker-up docker-down docker-logs exporter

setup:
	bash scripts/bootstrap.sh $(MONIKER)

finish:
	bash scripts/finish.sh

status:
	bash scripts/rpc.sh status

logs:
	sudo journalctl -u qubeticschain.service -n100 -f --no-pager

rpc-local:
	bash scripts/rpc.sh local

rpc-expose:
	ALLOW_IPS=$(ALLOW_IPS) DOMAIN=$(DOMAIN) bash scripts/rpc.sh expose

rpc-lockdown:
	bash scripts/rpc.sh lockdown

rpc-domain:
	DOMAIN=$(DOMAIN) ALLOW_IPS=$(ALLOW_IPS) EMAIL=$(EMAIL) bash scripts/rpc.sh domain

upgrade:
	VERSION=$(VERSION) bash scripts/upgrade.sh

snapshot:
        SNAPSHOT_DIR=$(SNAPSHOT_DIR) bash scripts/snapshot.sh

snapshot-restore:
        SNAP_URL=$(SNAP_URL) bash scripts/restore.sh

backup:
        BACKUP_DIR=$(BACKUP_DIR) BACKUP_PASSPHRASE=$(BACKUP_PASSPHRASE) bash scripts/backup.sh

monitor:
        RPC=$(RPC) REFERENCE_RPC=$(REFERENCE_RPC) bash scripts/monitor.sh

analyze-logs:
        SERVICE_NAME=$(SERVICE_NAME) SINCE=$(SINCE) bash scripts/analyze_logs.sh

tune:
        sudo bash scripts/tune.sh

benchmark:
        BENCHMARK_DURATION=$(DURATION) bash scripts/benchmark.sh

metrics:
        bash scripts/metrics.sh

exporter:
        python monitoring/exporter.py

docker-up:
	docker compose -f docker/docker-compose.yml up -d

docker-down:
	docker compose -f docker/docker-compose.yml down

docker-logs:
	docker compose -f docker/docker-compose.yml logs -f
