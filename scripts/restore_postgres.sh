#!/usr/bin/env bash
# Restaure la base de PRODUCTION depuis une sauvegarde (par défaut : la plus récente).
# Usage : ./restore_postgres.sh [fichier.sql.gz] [--yes]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
FILE=""
ASSUME_YES="no"
for arg in "$@"; do
case "${arg}" in
--yes) ASSUME_YES="yes" ;;
*) FILE="${arg}" ;;
esac
done
[[ -n "${FILE}" ]] || FILE="$(latest_file "${BACKUP_DIR}/postgres" 'pg_*.sql.gz')"
[[ -f "${FILE}" ]] || die "Aucune sauvegarde à restaurer"
require_container "${PG_CONTAINER}"
if [[ "${ASSUME_YES}" != "yes" ]]; then
read -r -p "Restaurer ${FILE} sur la base de PRODUCTION ? [oui/NON] " answer
[[ "${answer}" == "oui" ]] || die "Restauration annulée"
fi
SECONDS=0
log WARN "Restauration de ${FILE} sur la production"
gunzip -c "${FILE}" | docker exec -i "${PG_CONTAINER}" \
sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -q' >/dev/null
log INFO "Restauration terminée en ${SECONDS}s"
