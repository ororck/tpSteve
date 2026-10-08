# Étape 7 : namespace prod et limitation de ressources (O7)

## Objectif

Créer un namespace `prod` et y limiter la consommation de ressources avec un ResourceQuota. Un LimitRange fournit des requests et limits par défaut, sinon le quota rejette tout pod qui ne déclare pas ses ressources. Les valeurs sont arbitraires.

## Mise en place

```bash
kubectl apply -f manifests/o7-namespace-prod.yaml
kubectl apply -f manifests/o7-resourcequota.yaml
kubectl apply -f manifests/o7-limitrange.yaml
kubectl describe resourcequota prod-quota -n prod
kubectl describe limitrange prod-limits -n prod
kubectl get pods -n prod
```

Manifestes appliqués :

- `manifests/o7-namespace-prod.yaml`
- `manifests/o7-resourcequota.yaml` : `requests.cpu 1`, `requests.memory 1Gi`, `limits.cpu 2`, `limits.memory 2Gi`, `pods 10`
- `manifests/o7-limitrange.yaml` : par défaut `requests` 100m et 128Mi, `limits` 200m et 256Mi

Le manifeste `manifests/o7-test-pod-sans-requests.yaml` décrit un pod sans section `resources`, pour vérifier l'injection des valeurs par défaut.

## Résultat

```text
Resource         Used   Hard
limits.cpu       200m   2
limits.memory    256Mi  2Gi
pods             1      10
requests.cpu     100m   1
requests.memory  128Mi  1Gi

Type        Resource  Default Request  Default Limit
Container   cpu       100m             200m
Container   memory    128Mi            256Mi
```

Le pod `test-sans-requests` est `Running` dans `prod` et consomme 100m de CPU et 128Mi de requests, soit les valeurs par défaut du LimitRange : le LimitRange injecte bien les ressources manquantes.