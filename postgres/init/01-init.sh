#!/bin/bash
# Exécuté une seule fois, au premier démarrage du volume de données.
set -euo pipefail
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
-- Rôle applicatif : droits minimaux (ni superuser, ni CREATEDB, ni CREATEROLE)
CREATE ROLE ${APP_DB_USER} LOGIN PASSWORD '${APP_DB_PASSWORD}'
NOSUPERUSER NOCREATEDB NOCREATEROLE;
-- Rôle de supervision : lecture des statistiques uniquement
CREATE ROLE exporter LOGIN PASSWORD '${EXPORTER_DB_PASSWORD}';
GRANT pg_monitor TO exporter;
-- Table applicative
CREATE TABLE users (
id BIGSERIAL PRIMARY KEY,
name TEXT NOT NULL,
email TEXT NOT NULL,
created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Jeu de données volontairement volumineux (exercice EXPLAIN ANALYZE)
INSERT INTO users (name, email)
SELECT 'User ' || g, 'user' || g || '@example.com'
FROM generate_series(1, 500000) AS g;
-- Privilèges : l'application peut lire/écrire, mais pas modifier le schéma
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO ${APP_DB_USER};
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO ${APP_DB_USER};
GRANT USAGE, SELECT ON SEQUENCE users_id_seq TO ${APP_DB_USER};
ANALYZE users;
EOSQL
