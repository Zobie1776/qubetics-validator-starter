SHELL := /bin/bash

.PHONY: setup finish status logs rpc-local rpc-expose rpc-lockdown docker-up docker-down docker-logs

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

docker-up:
	docker compose -f docker/docker-compose.yml up -d

docker-down:
	docker compose -f docker/docker-compose.yml down

docker-logs:
	docker compose -f docker/docker-compose.yml logs -f
