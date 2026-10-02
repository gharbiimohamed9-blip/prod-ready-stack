# INC-001 : PostgreSQL indisponible
| | |
|---|---|
| **Date** | ___ |
| **Type** | Simulation : `docker stop prs-postgres` |
| **Gravité** | Critique (toutes les routes `/users` en erreur) |
| **Durée d'indisponibilité** | ___ s *(mesurée)* |
## Symptômes
`GET /users` renvoie `503 {"detail":"PostgreSQL indisponible"}`. `GET /ready` renvoie
`{"postgres":"down","mongo":"ok"}`.
`GET /events` (MongoDB) continue de fonctionner : la panne est partielle.
## Détection
- Alerte `PostgresDown` (Alertmanager) reçue à ___ (délai : ___ s après l'arrêt).
- Panneau "Cibles DOWN" / "Connexions PostgreSQL" du dashboard Grafana.
- Loki : `{service="api"} |= "PostgreSQL indisponible"`.
## Diagnostic
```bash
docker ps -a --filter name=prs-postgres # statut Exited
docker logs --tail 30 prs-postgres # arrêt propre ("received fast shutdown request")
docker inspect -f '{{.State.ExitCode}} OOM={{.State.OOMKilled}}' prs-postgres
curl -sk https://localhost/ready
```
Résultat : ___ (exit code, OOM ou non).
## Résolution
```bash
docker start prs-postgres
docker inspect -f '{{.State.Health.Status}}' prs-postgres # attendre "healthy"
curl -sk https://localhost/users | head -c 200
```
Durée totale : ___ s. L'alerte passe à "resolved" à ___.
## Cause racine
Arrêt manuel volontaire (simulation). En production, causes fréquentes : OOM kill, disque plein,
corruption, mise à jour mal planifiée.
## Variante : crash au lieu d'arrêt
`docker kill prs-postgres` simule un crash : grâce à `restart: unless-stopped`, Docker relance le
conteneur seul.
Temps de reprise automatique mesuré : ___ s.
## Impact
Données perdues : aucune (volume persistant `pg-data`). Requêtes en erreur : ___.
## Prévention
- `restart: unless-stopped` + healthcheck TCP (reprise automatique sur crash).
- Alerte `PostgresDown` avec `for: 30s` pour éviter les faux positifs.
- Gestion d'erreur côté API : 503 explicite plutôt qu'un plantage.
- À étudier : réplication (standby) pour supprimer le point de défaillance unique.
