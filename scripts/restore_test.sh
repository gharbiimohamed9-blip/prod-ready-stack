#!/usr/bin/env bash
# Prouve qu'une sauvegarde est réellement restaurable : on la restaure dans des
# conteneurs jetables (la production n'est jamais touchée) puis on compte les données.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
SCRATCH_PG="prs-restore-pg"
SCRATCH_MONGO="prs-restore-mongo"
cleanup() { docker rm -f "${SCRATCH_PG}" "${SCRATCH_MONGO}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
trap 'log ERROR "Test de restauration ÉCHOUÉ (ligne ${LINENO})"' ERR
# wait_until <secondes> <commande...> : réessaie chaque seconde
wait_until() {
local timeout="$1" i=0
shift
until "$@" >/dev/null 2>&1; do
i=$((i + 1))
[[ "${i}" -lt "${timeout}" ]] || return 1
sleep 1
done
}
test_postgres() {
local file image app_user restored current
file="$(latest_file "${BACKUP_DIR}/postgres" 'pg_*.sql.gz')"
[[ -n "${file}" ]] || die "Aucune sauvegarde PostgreSQL trouvée"
log INFO "PostgreSQL : restauration de test de $(basename "${file}")"
image="$(docker inspect -f '{{.Config.Image}}' "${PG_CONTAINER}")"
app_user="$(docker exec "${PG_CONTAINER}" printenv APP_DB_USER)"
docker run -d --name "${SCRATCH_PG}" -e POSTGRES_PASSWORD=scratch \
-e POSTGRES_DB=restore_check "${image}" >/dev/null
wait_until 60 docker exec "${SCRATCH_PG}" pg_isready -h 127.0.0.1 -U postgres \
|| die "Le conteneur PostgreSQL jetable ne démarre pas"
# Le dump contient des GRANT vers le rôle applicatif : il doit exister
docker exec "${SCRATCH_PG}" psql -U postgres -d restore_check -qc "CREATE ROLE ${app_user};"
gunzip -c "${file}" | docker exec -i "${SCRATCH_PG}" \
psql -U postgres -d restore_check -v ON_ERROR_STOP=1 -q >/dev/null
restored="$(docker exec "${SCRATCH_PG}" \
psql -U postgres -d restore_check -tAc 'SELECT count(*) FROM users;')"
current="$(docker exec "${PG_CONTAINER}" sh -c \
'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT count(*) FROM users;"')"
[[ "${restored}" -gt 0 ]] || die "Restauration PostgreSQL : table users vide"
log INFO "PostgreSQL OK : ${restored} lignes restaurées (production actuelle : ${current})"
}
test_mongo() {
local file image db count
file="$(latest_file "${BACKUP_DIR}/mongo" 'mongo_*.archive.gz')"
[[ -n "${file}" ]] || die "Aucune sauvegarde MongoDB trouvée"
log INFO "MongoDB : restauration de test de $(basename "${file}")"
image="$(docker inspect -f '{{.Config.Image}}' "${MONGO_CONTAINER}")"
db="$(docker exec "${MONGO_CONTAINER}" printenv MONGO_APP_DB)"
docker run -d --name "${SCRATCH_MONGO}" "${image}" >/dev/null
wait_until 60 docker exec "${SCRATCH_MONGO}" mongosh --quiet --eval "db.adminCommand('ping').ok" \
|| die "Le conteneur MongoDB jetable ne démarre pas"
docker exec -i "${SCRATCH_MONGO}" mongorestore --archive --gzip --quiet < "${file}"
count="$(docker exec "${SCRATCH_MONGO}" mongosh --quiet \
--eval "db.getSiblingDB('${db}').events.countDocuments({})")"
if [[ "${count}" -eq 0 ]]; then
log WARN "MongoDB : restauration réussie mais collection events vide"
else
log INFO "MongoDB OK : ${count} documents restaurés"
fi
}
SECONDS=0
require_container "${PG_CONTAINER}"
require_container "${MONGO_CONTAINER}"
test_postgres
cleanup
test_mongo
log INFO "Test de restauration RÉUSSI en ${SECONDS}s"

