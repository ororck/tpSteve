# Sécurisation d'un cluster AKS

Travaux pratiques de sécurisation du cluster AKS `tp-aks-sec-cluster` : authentification Entra ID, autorisations Azure RBAC, verrouillage des comptes locaux, limitation de ressources et restriction d'accès au serveur d'API.

## Dossiers et fichiers

- `etapes/` : une fiche par étape, avec l'objectif, les commandes exécutées et le résultat obtenu.
- `manifests/` : manifestes Kubernetes appliqués (pod et Secret de démonstration `o1-*`, namespace, quota et limites `o7-*`).
- `scripts/` : `securiser-aks.sh`, script idempotent qui applique le plan, avec un mode `--dry-run`.
- `schemas/` : schéma draw.io des groupes Entra, des rôles et du cluster.
- `preuves/` : captures de sorties de commandes.
- `o8-authentification-pod-sans-access-key.md` : explication de l'authentification d'un pod sans access-key (O8).

## Ordre de lecture

1. `etapes/01-contexte-et-droits.md`
2. `etapes/02-situation-critique-o1.md`
3. `etapes/03-resolution-formateur.md`
4. `etapes/04-groupes-et-integration-entra.md`
5. `etapes/05-autorisations-groupes-o6.md`
6. `etapes/06-verrouillage-comptes-locaux.md`
7. `etapes/07-namespace-prod-limitation-o7.md`
8. `etapes/08-explication-o8.md`
9. `etapes/09-whitelist-ip-o2-preparation.md`
10. `etapes/10-bonus-schema-et-script.md`
