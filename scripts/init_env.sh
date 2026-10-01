#!/usr/bin/env bash
# Crée .env à partir de .env.example avec des mots de passe aléatoires.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [[ -f .env ]]; then
echo ".env existe déjà : rien à faire (supprimez-le pour le régénérer)."
exit 0
fi
cp .env.example .env
for key in POSTGRES_PASSWORD APP_DB_PASSWORD EXPORTER_DB_PASSWORD \
MONGO_ROOT_PASSWORD MONGO_APP_PASSWORD MONGO_EXPORTER_PASSWORD \
GRAFANA_ADMIN_PASSWORD; do
sed -i "s|^${key}=.*|${key}=$(openssl rand -hex 16)|" .env
done
chmod 600 .env
echo ".env créé. Identifiants Grafana :"
grep -E '^GRAFANA_ADMIN_(USER|PASSWORD)=' .env
