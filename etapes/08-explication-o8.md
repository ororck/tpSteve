# Étape 8 : authentification d'un pod sans access-key (O8)

## Objectif

Expliquer comment un pod peut s'authentifier auprès d'un service Azure sans stocker d'access-key : Microsoft Entra Workload ID, par fédération OIDC entre le compte de service Kubernetes et une identité managée. Le livrable est un document, rien n'est implémenté.

## Mise en place

Le livrable est `o8-authentification-pod-sans-access-key.md`. Les commandes exécutées sont des lectures qui vérifient qu'aucune ressource n'a été créée pour cet objectif :

```bash
az aks show -g msaidiRG -n tp-aks-sec-cluster --query "{oidc:oidcIssuerProfile.enabled,wi:securityProfile.workloadIdentity}" -o json
az identity list -g msaidiRG --query "[].name" -o tsv
kubectl get secret/demo-secret pod/demo-pod -n default
```

## Résultat

- `oidcIssuerProfile.enabled` vaut `true` : valeur par défaut de la plateforme sur ce cluster, pas une action de cette étape.
- `securityProfile.workloadIdentity` vaut `null` : le webhook Workload Identity n'est pas activé.
- `az identity list -g msaidiRG` ne renvoie aucune identité managée.
- `demo-secret` et `demo-pod` sont toujours présents dans `default`.
