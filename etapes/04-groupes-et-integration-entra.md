# Étape 4 : groupes Entra et intégration Entra (O3, O4, O5)

## Objectif

Authentifier les accès au cluster avec Entra ID (O3) et les autoriser avec Azure RBAC. Deux groupes de sécurité sont créés : `tp-aks-sec-admins` (O4) et `tp-aks-sec-readers` (O5), chacun avec un seul membre. L'option `--aad-admin-group-object-ids` n'est pas utilisée, pour que toute autorisation passe par une assignation de rôle Azure. L'intégration Entra ne peut pas être désactivée une fois activée.

## Mise en place

```bash
az ad group create --display-name tp-aks-sec-admins  --mail-nickname tp-aks-sec-admins \
  --description "Administrateurs du cluster tp-aks-sec-cluster"
az ad group create --display-name tp-aks-sec-readers --mail-nickname tp-aks-sec-readers \
  --description "Lecteurs du cluster tp-aks-sec-cluster"
az ad group member add --group 05d2df4d-aa8c-4e6f-918d-d5bb0e99ed71 --member-id da606902-545b-44f5-8107-de279d199223
az ad group member add --group 58f3f205-00e1-42ed-9082-4caa698ebd5b --member-id e7cbea33-8e5d-4a20-9823-d1281d600761

az aks update --resource-group msaidiRG --name tp-aks-sec-cluster --enable-aad --enable-azure-rbac

az aks get-credentials -g msaidiRG -n tp-aks-sec-cluster --file .kcfg-tp --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
```

`kubelogin` v0.2.19 provient de la release GitHub officielle, installé dans `~/.local/bin`.

## Résultat

Sortie de `az aks update` pour `aadProfile` :

```json
"aadProfile": {
  "adminGroupObjectIDs": null,
  "enableAzureRbac": true,
  "managed": true,
  "tenantId": "a2e466aa-4f86-4545-b5b8-97da7c8febf3"
},
"enableRbac": true
```

Groupes :

- `tp-aks-sec-admins` (`05d2df4d-aa8c-4e6f-918d-d5bb0e99ed71`) : `msaidi.ext@simplonformations.co`.
- `tp-aks-sec-readers` (`58f3f205-00e1-42ed-9082-4caa698ebd5b`) : `stheval@simplonformations.co`.

Avant les assignations de l'étape 5, un `kubectl get namespaces` avec le kubeconfig Entra renvoie `Forbidden` : l'utilisateur est authentifié, aucun rôle ne l'autorise encore.

Kubernetes RBAC reste actif (`enableRbac: true`). Les `RoleBinding` et `ClusterRoleBinding` du cluster sont à auditer séparément des rôles Azure.
