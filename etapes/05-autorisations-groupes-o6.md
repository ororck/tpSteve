# Étape 5 : autorisations des deux groupes (O6)

## Objectif

Donner au groupe admins les droits d'administration du cluster et au groupe readers un accès en lecture seule, par des assignations de rôles Azure RBAC à la portée du cluster. Aucune assignation n'est faite au niveau du groupe de ressources ni de l'abonnement.

## Mise en place

```bash
AKS_ID=$(az aks show -g msaidiRG -n tp-aks-sec-cluster --query id -o tsv)
az role assignment create --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --assignee-object-id 05d2df4d-aa8c-4e6f-918d-d5bb0e99ed71 --assignee-principal-type Group --scope $AKS_ID
az role assignment create --role "Azure Kubernetes Service RBAC Reader" \
  --assignee-object-id 58f3f205-00e1-42ed-9082-4caa698ebd5b --assignee-principal-type Group --scope $AKS_ID

az ad group member check --group 05d2df4d-aa8c-4e6f-918d-d5bb0e99ed71 --member-id <object-id-utilisateur>
az role assignment list --assignee 05d2df4d-aa8c-4e6f-918d-d5bb0e99ed71 --scope $AKS_ID \
  --role "Azure Kubernetes Service RBAC Cluster Admin"
az aks get-credentials -g msaidiRG -n tp-aks-sec-cluster --file .kcfg-tp --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl get ns
```

## Résultat

- Le compte `msaidi.ext@simplonformations.co` est membre effectif de `tp-aks-sec-admins` (`member check` renvoie `true`).
- Assignations sur `/subscriptions/5e683e0f-b00c-48d6-9769-5aaf598de8f1/resourceGroups/msaidiRG/providers/Microsoft.ContainerService/managedClusters/tp-aks-sec-cluster` :
  - `Azure Kubernetes Service RBAC Cluster Admin` : groupe `tp-aks-sec-admins` ;
  - `Azure Kubernetes Service RBAC Reader` : groupe `tp-aks-sec-readers`.
- `kubectl get ns` avec le kubeconfig Entra réussit (la propagation du rôle prend environ 3 minutes) :

```text
NAME              STATUS   AGE
default           Active   46m
kube-node-lease   Active   46m
kube-public       Active   46m
kube-system       Active   46m
prod              Active   20m
```

- L'accès du groupe readers (`stheval@simplonformations.co`) n'est pas testé en direct.
