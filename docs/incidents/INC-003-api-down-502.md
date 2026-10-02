# INC-003 : API arrêtée, Nginx répond 502
| | |
|---|---|
| **Date** | ___ |
| **Type** | Simulation : `docker stop prs-api` |
| **Gravité** | Critique (service totalement indisponible) |
| **Durée d'indisponibilité** | ___ s |
## Symptômes
```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/health # 502
```
## Détection
- Alerte `TargetDown` (job `api`) reçue à ___ (délai : ___ s).
- Loki : `{service="nginx"} | json | status = 502` et message d'erreur Nginx "api could not be
resolved".
- Dashboard : cibles DOWN = 1.
## Diagnostic
```bash
docker ps -a --filter name=prs-api # Exited
docker logs --tail 30 prs-api # dernière activité avant l'arrêt
docker logs --tail 20 prs-nginx
```
Constat : Nginx est sain, c'est l'amont (API) qui est absent.
## Résolution
```bash
docker start prs-api
curl -sk https://localhost/health # 200, SANS recharger Nginx
```
Durée totale : ___ s.
## Cause racine
Arrêt manuel volontaire (simulation). En production : crash applicatif, OOM, déploiement raté.
## Impact
Toutes les requêtes en erreur pendant ___ s. Aucune perte de données.
## Prévention
- `resolver 127.0.0.11` + variable dans `proxy_pass` : Nginx re-résout `api` et reprend seul quand
l'API revient (sans cela, il garderait une IP périmée et le 502 persisterait jusqu'à un reload).
- Healthcheck + `restart: unless-stopped` : l'API crashée est relancée automatiquement.
- À étudier : plusieurs instances de l'API derrière Nginx (`upstream`) pour supprimer le point de
défaillance.
