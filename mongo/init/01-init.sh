#!/bin/bash
# Exécuté une seule fois, au premier démarrage du volume de données.
set -euo pipefail
mongosh --quiet \
-u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
--authenticationDatabase admin <<EOF_JS
// Utilisateur applicatif : readWrite sur UNE seule base
db = db.getSiblingDB("${MONGO_APP_DB}");
db.createUser({
user: "${MONGO_APP_USER}",
pwd: "${MONGO_APP_PASSWORD}",
roles: [{ role: "readWrite", db: "${MONGO_APP_DB}" }]
});
db.createCollection("events");
db.events.createIndex({ created_at: -1 });
// Utilisateur de supervision pour mongodb_exporter
db = db.getSiblingDB("admin");
db.createUser({
user: "exporter",
pwd: "${MONGO_EXPORTER_PASSWORD}",
roles: [
Production-Ready Stack : guide pas à pas
VirtualBox / Linux Mint / Docker Compose Page 15
{ role: "clusterMonitor", db: "admin" },
{ role: "read", db: "local" }
]
});
EOF_JS
