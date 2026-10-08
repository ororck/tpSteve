# Étape 3 : résolution de l'object ID du formateur

## Objectif

Obtenir l'object ID Entra du formateur, `stheval@simplonformations.co`, pour l'ajouter seul au groupe readers à l'étape 4. La résolution se fait par UPN exact, jamais par nom affiché.

## Mise en place

```bash
az ad user show --id stheval@simplonformations.co \
  --query "{id:id,userPrincipalName:userPrincipalName,displayName:displayName,accountEnabled:accountEnabled}" -o json
```

## Résultat

```json
{
  "accountEnabled": null,
  "displayName": "Steve THEVAL",
  "id": "e7cbea33-8e5d-4a20-9823-d1281d600761",
  "userPrincipalName": "stheval@simplonformations.co"
}
```

L'object ID retenu est `e7cbea33-8e5d-4a20-9823-d1281d600761`. `accountEnabled` vaut `null` parce que la commande ne sélectionne pas ce champ par défaut. L'état du compte n'a pas été vérifié autrement.
