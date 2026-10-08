# Étape 6 : verrouillage des comptes locaux (O6)

## Objectif

Supprimer la possibilité de télécharger un kubeconfig à certificat client (`--admin`) pour que seuls les membres des deux groupes Entra accèdent au cluster. La désactivation n'est lancée qu'après avoir vérifié trois points : l'utilisateur est membre du groupe admins, l'assignation `Cluster Admin` est visible sur le cluster, et `kubectl get ns` réussit avec le kubeconfig Entra (étape 5).

## Mise en place

```bash
az aks update --resource-group msaidiRG --name tp-aks-sec-cluster --disable-local-accounts
az aks show -g msaidiRG -n tp-aks-sec-cluster --query "{prov:provisioningState,localOff:disableLocalAccounts,rbac:aadProfile.enableAzureRbac}" -o json
az aks get-credentials -g msaidiRG -n tp-aks-sec-cluster --admin
kubectl get ns
```

## Résultat

```json
{ "localOff": true, "prov": "Succeeded", "rbac": true }
```

`az aks get-credentials --admin` est refusé :

```text
Code: BadRequest
Message: Getting static credential is not allowed because this cluster is set to disable local accounts.
```

`kubectl get ns` avec le kubeconfig Entra réussit toujours après la désactivation.

La rotation des certificats (`az aks rotate-certs`) n'est pas effectuée. Un certificat admin téléchargé avant la désactivation n'est pas révoqué par `--disable-local-accounts`.
