# Étape 2 : cluster de test en situation critique (O1)

## Objectif

Reproduire l'état de départ décrit par le sujet : un cluster AKS en mode « Local RBAC », sans intégration Entra ID, avec comptes locaux actifs, API publique sans restriction d'IP et monitoring Azure désactivé. Il sert de base pour appliquer et tester les étapes suivantes. Un Secret factice et un pod qui le monte représentent une charge de travail existante.

## Mise en place

Ni `--enable-aad` ni `--enable-azure-rbac` ne sont passés : `aadProfile` reste `null`, `disableLocalAccounts` reste `false`, `enableRbac` reste `true`.

```bash
az aks create --resource-group msaidiRG --name tp-aks-sec-cluster --location westeurope \
  --node-count 1 --node-vm-size Standard_D2s_v3 --tier free \
  --enable-managed-identity --no-ssh-key

az aks get-credentials -g msaidiRG -n tp-aks-sec-cluster --file .kcfg-tp
kubectl apply --dry-run=client -f manifests/o1-demo-secret.yaml
kubectl apply --dry-run=client -f manifests/o1-demo-pod.yaml
kubectl apply -f manifests/o1-demo-secret.yaml -f manifests/o1-demo-pod.yaml
```

Manifestes appliqués :

- `manifests/o1-demo-secret.yaml`
- `manifests/o1-demo-pod.yaml`

## Résultat

Profil du cluster à la création (`az aks show`) :

```json
"aadProfile": null,
"apiServerAccessProfile": null,
"addonProfiles": null,
"azureMonitorProfile": null,
"disableLocalAccounts": false,
"enableRbac": true,
"agentPools": [{ "count": 1, "mode": "System", "name": "nodepool1", "vmSize": "Standard_D2s_v3" }],
"kubernetesVersion": "1.35",
"sku": { "name": "Base", "tier": "Free" }
```

- Les policies de l'organisation (groupe d'administration `SimplonRacineAdmin`) refusent `Standard_D2als_v7` et `Standard_D2as_v7`. `Standard_D2s_v3` est acceptée.
- La policy de localisation n'autorise que `francecentral`, `westeurope`, `francesouth`, `germanynorth`, `norwaywest` et `northeurope`. Le cluster est créé en `westeurope`.
- Le Secret `demo-secret` et le pod `demo-pod` existent dans le namespace `default`, le pod est `Running` :

```text
NAME           READY   STATUS    RESTARTS   AGE
pod/demo-pod   1/1     Running   0          111m
NAME                 TYPE     DATA   AGE
secret/demo-secret   Opaque   1      111m
```

- Dans cet état, `az aks get-credentials --admin` fournit un certificat client du groupe `system:masters`, qui contourne toute autorisation Kubernetes RBAC et n'est pas auditable nominativement.
