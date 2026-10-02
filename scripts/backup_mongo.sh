#!/usr/bin/env bash
# Sauvegarde de MongoDB : mongodump --archive --gzip, horodaté, avec rétention.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
OUT_DIR="${BACKUP_DIR}/mongo"
TS="$(date +%Y%m%d_%H%M%S)"
FINAL="${OUT_DIR}/mongo_${TS}.archive.gz"
TMP="${FINAL}.tmp"
mkdir -p "${OUT_DIR}"
trap 'rm -f "${TMP}"' EXIT
trap 'log ERROR "Échec de la sauvegarde MongoDB (ligne ${LINENO})"' ERR
require_container "${MONGO_CONTAINER}"
log INFO "Début sauvegarde MongoDB -> ${FINAL}"
docker exec "${MONGO_CONTAINER}" sh -c \
'mongodump --archive --gzip --quiet \
-u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
--authenticationDatabase admin --db "$MONGO_APP_DB"' \
> "${TMP}"
[[ "$(stat -c%s "${TMP}")" -gt 100 ]] || die "Archive anormalement petite"
mv "${TMP}" "${FINAL}"
log INFO "Sauvegarde OK ($(du -h "${FINAL}" | cut -f1))"
DELETED="$(find "${OUT_DIR}" -name 'mongo_*.archive.gz' -type f \
-mtime "+${RETENTION_DAYS}" -print -delete | wc -l)"
log INFO "Rétention ${RETENTION_DAYS} j : ${DELETED} ancienne(s) sauvegarde(s) supprimée(s)"
