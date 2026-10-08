# Étape 1 : contexte et audit des droits

## Objectif

Vérifier, avant toute écriture, que le compte utilisé détient les droits nécessaires à chaque objectif du TP (création du cluster, groupes Entra, assignations de rôles). Cette étape est en lecture seule.

## Mise en place

```bash
az account show -o json
az ad signed-in-user show --query "{id:id,upn:userPrincipalName,displayName:displayName}" -o json
az role assignment list --assignee <object-id-utilisateur> --all --include-inherited --include-groups \
  --query "[].{role:roleDefinitionName,scope:scope,principalType:principalType,principalName:principalName}" -o table
az rest --method GET --url https://graph.microsoft.com/v1.0/policies/authorizationPolicy \
  --query "{allowedToCreateSecurityGroups:defaultUserRolePermissions.allowedToCreateSecurityGroups}"
az rest --method GET --url "https://management.azure.com/subscriptions/<sub>/providers/Microsoft.Authorization/permissions?api-version=2022-04-01"
az role definition list --name "<rôle>"
az vm list-usage -l westeurope
az vm list-skus -l westeurope --resource-type virtualMachines
```

## Résultat

- Tenant `Simplonformations.co` (`a2e466aa-4f86-4545-b5b8-97da7c8febf3`), abonnement `OCC_Toulouse_AdminCloud_190227_INTENSIF-PRF-2026`.
- Utilisateur `msaidi.ext@simplonformations.co`, object ID `da606902-545b-44f5-8107-de279d199223`, sans rôle de répertoire Entra.
- Rôles Azure de l'utilisateur :
  - `Reader` et `Role Based Access Control Administrator` à la portée de l'abonnement ;
  - `Owner`, `Contributor` et `Reader` sur `resourceGroups/msaidiRG`.
- `allowedToCreateSecurityGroups = true` : l'utilisateur peut créer des groupes de sécurité et en devient propriétaire.
- À la portée de l'abonnement, l'utilisateur n'a pas `Microsoft.Resources/subscriptions/resourceGroups/write`. Le cluster est donc créé dans le groupe de ressources existant `msaidiRG`.
- `managedClusters/write` est couvert par `Owner` sur `msaidiRG`. `roleAssignments/write` sur le cluster est couvert par `Role Based Access Control Administrator`.
- Tailles de VM sans restriction dans `westeurope` avec au moins 2 vCPU et 4 Go : `Standard_D2als_v7`, `Standard_D2alds_v7`, `Standard_F2als_v7`, `Standard_F2alds_v7`. Les policies de l'organisation refusent ensuite plusieurs de ces tailles (voir l'étape 2).
