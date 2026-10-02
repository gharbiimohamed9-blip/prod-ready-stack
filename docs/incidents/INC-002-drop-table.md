# INC-002 : Suppression accidentelle d'une table (restauration depuis sauvegarde)
| | |
|---|---|
| **Date** | ___ |
| **Type** | Simulation : `DROP TABLE users;` exécuté par un administrateur |
| **Gravité** | Critique (perte de données) |
| **Temps de restauration (RTO)** | ___ s *(affiché par `restore_postgres.sh`)* |
## Préparation
```bash
make backup # sauvegarde fraîche
curl -sk -X POST https://localhost/users -H 'Content-Type: application/json' \
-d '{"name":"Apres backup","email":"apres@example.com"}' # donnée créée APRÈS la sauvegarde
```
Lignes dans `users` avant l'incident : ___
## Test de moindre privilège (prévention)
Le compte applicatif ne peut pas détruire le schéma :
```bash
docker exec prs-postgres sh -c 'psql -U "$APP_DB_USER" -d "$POSTGRES_DB" -c "DROP TABLE users;"'
# ERROR: must be owner of table users
```
## Symptômes
Après le `DROP` par l'administrateur : `GET /users` renvoie `500`.
## Détection
- Alerte `ApiServerErrors` (taux de 5xx > 0).
- Loki : `{service="api"} |= "UndefinedTable"` : `relation "users" does not exist`.
## Diagnostic
```bash
docker logs --tail 20 prs-api
docker exec prs-postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt"'
```
Résultat : table `users` absente.
## Résolution
```bash
./scripts/restore_postgres.sh # répondre "oui"
curl -sk https://localhost/users | head -c 200
```
Lignes après restauration : ___. Durée de la restauration : ___ s.
## Cause racine
Commande destructrice exécutée sur la production sans garde-fou (simulation d'une erreur humaine).
## Impact
- Indisponibilité de `/users` pendant ___ s.
- **Perte de données (RPO)** : la ligne créée après la sauvegarde est perdue (___ ligne(s)).
## Prévention
- Compte applicatif sans droit DDL (démontré ci-dessus).
- Sauvegardes plus fréquentes pour réduire le RPO ; archivage WAL (PITR) pour descendre à quelques
secondes.
- `restore_test.sh` planifié : une sauvegarde non testée n'est pas une sauvegarde.
- Accès administrateur nominatif et journalisé.
