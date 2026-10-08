# Étape 9 : plages IP autorisées sur le serveur d'API (O2)

## Objectif

Restreindre l'accès au serveur d'API du cluster aux plages IP autorisées (`--api-server-authorized-ip-ranges`), pour qu'il ne soit plus joignable depuis tout Internet. L'IP de sortie du cluster doit figurer dans la liste, et l'IP du poste qui applique la modification est ajoutée temporairement, puis retirée.

## Mise en place

Lectures seules, pour récupérer l'état courant et l'IP de sortie du cluster :

```bash
az aks show -g msaidiRG -n tp-aks-sec-cluster \
  --query "{api:apiServerAccessProfile,outbound:networkProfile.outboundType,ips:networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id}" -o json
az network public-ip show --ids <id retourné ci-dessus> --query "{name:name,ip:ipAddress}" -o json
```

Simulation de l'application avec une plage de documentation (RFC 5737), sans écriture :

```bash
./scripts/securiser-aks.sh --cluster tp-aks-sec-cluster --resource-group msaidiRG \
  --admins-group-id 05d2df4d-aa8c-4e6f-918d-d5bb0e99ed71 \
  --readers-group-id 58f3f205-00e1-42ed-9082-4caa698ebd5b \
  --ip-range 203.0.113.0/24 --dry-run
```

## Résultat

Le serveur d'API `tp-aks-sec-msaidirg-5e683e-03y6zbip.hcp.westeurope.azmk8s.io` n'accepte que les plages autorisées. `az aks show` renvoie :

```json
{ "prov": "Succeeded", "ranges": ["86.201.70.133/32"] }
```

- La seule plage autorisée est `86.201.70.133/32`, l'IP publique du poste d'administration.
- `kubectl get ns` avec le kubeconfig Entra réussit depuis ce poste.
- Le type de sortie du cluster est `loadBalancer`, avec l'IP de sortie `108.141.95.52`, qui ne figure pas dans la liste autorisée.
- Le dry-run du script affiche les deux mises à jour prévues, dans cet ordre :

```text
Étape 5, phase 1 : plage + IP de sortie + IP courante temporaire
az aks update -g msaidiRG -n tp-aks-sec-cluster --api-server-authorized-ip-ranges <plage>,108.141.95.52/32,<IP courante>/32
Étape 5, phase 2 : retrait de l'IP courante
az aks update -g msaidiRG -n tp-aks-sec-cluster --api-server-authorized-ip-ranges <plage>,108.141.95.52/32
```

- Depuis une IP hors de la liste, `kubectl get ns` n'aboutit pas :

```text
Unable to connect to the server: net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)
```
