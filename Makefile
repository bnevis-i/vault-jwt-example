.PHONY: run exec down clean

run:
	docker compose build
	docker compose up -d
	docker logs -f edgex-vault

exec:
	docker exec -ti -e VAULT_TOKEN=$(shell docker exec -ti edgex-vault jq -r .root_token /vault/config/assets/vault-init.json) edgex-vault sh -l

down:
	docker compsoe down

clean:
	docker compose down -v
