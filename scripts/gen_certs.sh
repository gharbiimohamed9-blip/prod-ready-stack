#!/usr/bin/env bash
# Génère un certificat TLS auto-signé pour Nginx (usage local uniquement).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/nginx/certs"
mkdir -p "${DIR}"
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
-keyout "${DIR}/server.key" -out "${DIR}/server.crt" \
-subj "/C=TN/O=Prod Ready Stack/CN=localhost" \
-addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null
chmod 600 "${DIR}/server.key"
echo "Certificat généré dans ${DIR}"
