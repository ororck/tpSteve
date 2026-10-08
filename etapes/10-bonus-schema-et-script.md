# Étape 10 : bonus, schéma et script

## Objectif

Fournir un schéma des groupes, des rôles et du cluster, et un script qui applique le plan de sécurisation sur un cluster existant de façon idempotente.

## Mise en place

Fichiers :

- `schemas/groupes-entra-roles-aks.drawio` : schéma à ouvrir avec app.diagrams.net ou l'extension draw.io de VS Code. Il représente les utilisateurs, les deux groupes Entra, les deux rôles AKS et leurs assignations, et le cluster.
- `scripts/securiser-aks.sh` : applique dans l'ordre l'intégration Entra avec Azure RBAC, les deux assignations de rôles, la désactivation des comptes locaux (seulement si un accès Entra non administrateur fonctionne), le namespace `prod` avec quota et LimitRange, puis les plages IP si `--ip-range` est fourni. Aucune assignation n'est supprimée.

Exécution en simulation sur le cluster :

```bash
./scripts/securiser-aks.sh --cluster tp-aks-sec-cluster --resource-group msaidiRG \
  --admins-group-id 05d2df4d-aa8c-4e6f-918d-d5bb0e99ed71 \
  --readers-group-id 58f3f205-00e1-42ed-9082-4caa698ebd5b \
  --ip-range 203.0.113.0/24 --dry-run
```

## Résultat

```text
Étape 1 : intégration Entra et Azure RBAC déjà actives, rien à rejouer.
Étape 2 : 'Azure Kubernetes Service RBAC Cluster Admin' déjà assigné à 05d2df4d-aa8c-4e6f-918d-d5bb0e99ed71.
Étape 2 : 'Azure Kubernetes Service RBAC Reader' déjà assigné à 58f3f205-00e1-42ed-9082-4caa698ebd5b.
Étape 3 : comptes locaux déjà désactivés.
Étape 4 : [dry-run] application du namespace, du quota et du limitrange.
Étape 5, phase 1 : plage + IP de sortie + IP courante temporaire
Étape 5, phase 2 : retrait de l'IP courante
```

Le script ne rejoue que ce qui manque, et les écritures sont seulement affichées en `--dry-run`. Le script est vérifié par `bash -n` (syntaxe). Le linter `shellcheck` n'est pas exécuté (non installé sur le poste).
