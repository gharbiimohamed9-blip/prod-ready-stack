#!/usr/bin/env bash
# Installe (ou met à jour) les tâches cron : sauvegardes + test de restauration.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TAG="# prod-ready-stack"
LOG="${PROJECT_DIR}/backups/cron.log"
mkdir -p "${PROJECT_DIR}/backups"
NEW_JOBS="0 2 * * * ${SCRIPT_DIR}/backup_postgres.sh >> ${LOG} 2>&1 ${TAG}
5 2 * * * ${SCRIPT_DIR}/backup_mongo.sh >> ${LOG} 2>&1 ${TAG}
30 2 * * * ${SCRIPT_DIR}/restore_test.sh >> ${LOG} 2>&1 ${TAG}"
# On conserve les autres tâches de l'utilisateur, on remplace uniquement les nôtres
{ crontab -l 2>/dev/null | grep -v "${TAG}" || true; echo "${NEW_JOBS}"; } | crontab -
echo "Tâches cron installées :"
crontab -l | grep "${TAG}"
