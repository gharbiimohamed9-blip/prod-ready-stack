#!/usr/bin/env bash
# Variables et fonctions communes. Ce fichier est "sourcé" par les autres scripts.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Charge .env s'il existe (RETENTION_DAYS, etc.)
if [[ -f "${PROJECT_DIR}/.env" ]]; then
set -a
# shellcheck disable=SC1091
source "${PROJECT_DIR}/.env"
set +a
fi
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_DIR}/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
PG_CONTAINER="${PG_CONTAINER:-prs-postgres}"
MONGO_CONTAINER="${MONGO_CONTAINER:-prs-mongo}"
LOG_FILE="${LOG_FILE:-${BACKUP_DIR}/backup.log}"
mkdir -p "${BACKUP_DIR}"
# log NIVEAU message... : écrit à l'écran ET dans le fichier de log
log() {
local level="$1"
shift
printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${level}" "$*" | tee -a "${LOG_FILE}"
}
die() {
log ERROR "$*"
exit 1
}
# Vérifie qu'un conteneur tourne
require_container() {
local state
state="$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || true)"
[[ "${state}" == "true" ]] || die "Le conteneur $1 n'est pas en cours d'exécution"
}
# Fichier le plus récent d'un dossier : latest_file <dossier> <motif>
latest_file() {
find "$1" -name "$2" -type f 2>/dev/null | sort | tail -n 1
}
