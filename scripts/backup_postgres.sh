#!/usr/bin/env bash
# Sauvegarde logique de PostgreSQL : pg_dump compressé, horodaté, avec rétention.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
OUT_DIR="${BACKUP_DIR}/postgres"
TS="$(date +%Y%m%d_%H%M%S)"
FINAL="${OUT_DIR}/pg_${TS}.sql.gz"
TMP="${FINAL}.tmp"
mkdir -p "${OUT_DIR}"
trap 'rm -f "${TMP}"' EXIT
trap 'log ERROR "Échec de la sauvegarde PostgreSQL (ligne ${LINENO})"' ERR
require_container "${PG_CONTAINER}"
log INFO "Début sauvegarde PostgreSQL -> ${FINAL}"
# Les variables POSTGRES_USER / POSTGRES_DB existent déjà DANS le conteneur :
# les guillemets simples les font évaluer là-bas (aucun secret sur la ligne de commande).
docker exec "${PG_CONTAINER}" sh -c \
'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean --if-exists' \
| gzip -9 > "${TMP}"
gzip -t "${TMP}" || die "Archive corrompue"
[[ "$(stat -c%s "${TMP}")" -gt 200 ]] || die "Archive anormalement petite"
mv "${TMP}" "${FINAL}"
log INFO "Sauvegarde OK ($(du -h "${FINAL}" | cut -f1))"
# Rétention : suppression des sauvegardes trop anciennes
DELETED="$(find "${OUT_DIR}" -name 'pg_*.sql.gz' -type f \
-mtime "+${RETENTION_DAYS}" -print -delete | wc -l)"
log INFO "Rétention ${RETENTION_DAYS} j : ${DELETED} ancienne(s) sauvegarde(s) supprimée(s)"
