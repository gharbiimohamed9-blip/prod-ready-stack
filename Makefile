COMPOSE = docker compose -f docker-compose.yml -f docker-compose.monitoring.yml

.PHONY: up down ps logs backup restore-test cron perf-demo lint clean

.env:
	./scripts/init_env.sh

nginx/certs/server.crt:
	./scripts/gen_certs.sh

up: .env nginx/certs/server.crt ## Démarre toute la stack
	$(COMPOSE) up -d --build

down: ## Arrête la stack (les données sont conservées)
	$(COMPOSE) down

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f --tail=100

backup: ## Sauvegarde PostgreSQL + MongoDB
	./scripts/backup_postgres.sh
	./scripts/backup_mongo.sh

restore-test: ## Prouve que les sauvegardes sont restaurables
	./scripts/restore_test.sh

cron: ## Planifie sauvegardes + test de restauration
	./scripts/install_cron.sh

perf-demo: ## Exercice EXPLAIN ANALYZE / index
	docker exec -i prs-postgres sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"' \
	< postgres/perf_demo.sql

lint:
	shellcheck -x --source-path=SCRIPTDIR scripts/*.sh postgres/init/*.sh mongo/init/*.sh
	docker compose --env-file .env.example \
		-f docker-compose.yml -f docker-compose.monitoring.yml config -q
	python3 -m py_compile api/app/main.py

clean: ## ATTENTION : supprime aussi les volumes (données)
	$(COMPOSE) down -v
