# O8 : comment un pod s'authentifie sur Azure sans access-key

Ce document est explicatif. Rien de ce qui suit n'a été mis en place sur le cluster du TP. Les commandes et les manifestes sont donnés à titre d'illustration.

## 1. Le mécanisme, et pourquoi il remplace une access-key

### Le problème de l'access-key

Une access-key (clé de compte de stockage, secret de principal de service, chaîne de connexion) est un **secret statique**. Pour qu'un pod l'utilise, il faut la stocker quelque part : un Secret Kubernetes, une variable d'environnement ou une image. Cela pose quatre problèmes :

- **Elle peut fuir.** On la retrouve dans un dépôt git, un log, un `kubectl get secret`. Le Secret de démonstration de O1 illustre ce risque : tout administrateur du cluster peut le lire.
- **Elle dure longtemps.** Une clé de stockage n'expire pas d'elle-même. Il faut organiser sa rotation, ce qui est souvent oublié.
- **Elle donne des droits larges.** Une clé de compte de stockage donne un accès complet au compte, sans granularité.
- **Elle n'est pas nominative.** Dans les journaux, on ne sait pas quel pod l'a utilisée.

### Le mécanisme : Microsoft Entra Workload ID, par fédération d'identité

Le mécanisme recommandé s'appelle **Microsoft Entra Workload ID**. Il repose sur la **fédération d'identité de charge de travail** (*workload identity federation*).

Le principe : le cluster Kubernetes devient un **fournisseur d'identité OIDC**. Il signe un jeton qui atteste « je suis le compte de service `X` du namespace `Y` ». Entra ID est configuré pour **faire confiance à ce fournisseur** pour ce compte de service précis. Il échange alors ce jeton contre un jeton d'accès Azure ([vue d'ensemble Workload ID sur AKS](https://learn.microsoft.com/azure/aks/workload-identity-overview)) :

> *"In this security model, the AKS cluster acts as the token issuer. Microsoft Entra ID uses OIDC to discover public signing keys and verify the authenticity of the service account token before exchanging it for a Microsoft Entra token."*

Ce qui change par rapport à une access-key :

| | Access-key | Workload ID |
|---|---|---|
| Secret stocké dans le cluster | Oui | **Non.** Il n'y a qu'un jeton éphémère, renouvelé par Kubernetes |
| Durée de vie | Illimitée ou très longue | Jeton Kubernetes : 1 h par défaut. Jeton Entra : 24 h au plus |
| Droits | Tout le compte | Rôle Azure précis, sur la ressource précise, via Azure RBAC |
| Traçabilité | Anonyme | Identité Entra dédiée, visible dans les journaux |
| Révocation | Régénérer la clé et redéployer partout | Supprimer la *federated credential* ou l'assignation de rôle |

Ce mécanisme remplace aussi l'ancien **pod-managed identity** (`aad-pod-identity`). Pour s'en passer, la documentation propose une migration, avec un sidecar temporaire qui convertit les appels IMDS en OIDC.

## 2. Comment il fonctionne concrètement

Il y a quatre acteurs :

- le **serveur d'API** du cluster, qui émet les jetons ;
- le **point de découverte OIDC** du cluster, qui publie les clés publiques ;
- **Entra ID**, qui vérifie et échange ;
- l'**identité Azure** : une identité managée affectée par l'utilisateur, ou une application Entra.

### Préalable, configuré une fois

1. Le cluster publie deux documents à une URL publique, l'**issuer URL** :
   - `{IssuerURL}/.well-known/openid-configuration` : le document de découverte OIDC ;
   - `{IssuerURL}/openid/v1/jwks` : les **clés publiques** qui signent les jetons de comptes de service.
2. Sur l'identité Azure, on crée une **federated identity credential**. C'est une règle de confiance qui dit : « j'accepte les jetons signés par l'issuer `https://...`, dont le sujet est `system:serviceaccount:<namespace>:<serviceaccount>` et l'audience `api://AzureADTokenExchange` ».
3. On donne à cette identité un **rôle Azure** sur la ressource cible, par exemple `Storage Blob Data Reader` sur un conteneur.
4. Le compte de service Kubernetes porte l'annotation `azure.workload.identity/client-id: <client-id de l'identité>`.

### À l'exécution, pour chaque pod

1. **Mutation.** Le pod porte le label `azure.workload.identity/use: "true"`. Le **webhook d'admission mutant** de Workload ID le modifie avant sa création. Il injecte :
   - un volume de **jeton de compte de service projeté**, dont l'audience est `api://AzureADTokenExchange` ;
   - les variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_FEDERATED_TOKEN_FILE` et `AZURE_AUTHORITY_HOST`.
2. **Émission du jeton par le cluster.** Le kubelet demande au serveur d'API un jeton pour ce compte de service (*Service Account Token Volume Projection*). Ce jeton est un JWT signé par la clé privée du cluster, avec les champs suivants :
   - `iss` : l'issuer URL ;
   - `sub` : `system:serviceaccount:ns:sa` ;
   - `aud` : `api://AzureADTokenExchange` ;
   - `exp` : 1 h par défaut.

   Le kubelet l'écrit dans le fichier désigné par `AZURE_FEDERATED_TOKEN_FILE`, et le **renouvelle avant expiration**.
3. **Échange.** L'application utilise le SDK Azure Identity (`DefaultAzureCredential` ou `WorkloadIdentityCredential`) ou MSAL. Le SDK lit le fichier et appelle le point de jeton Entra (`/oauth2/v2.0/token`) avec :
   - `grant_type=client_credentials` ;
   - `client_id` : l'identité Azure ;
   - `client_assertion` : le jeton Kubernetes ;
   - `scope` : la ressource, par exemple `https://storage.azure.com/.default`.
4. **Vérification par Entra ID.** Entra ID :
   1. lit l'`iss` du jeton ;
   2. récupère le document de découverte puis les JWKS à cette URL ;
   3. vérifie la signature ;
   4. vérifie que `iss`, `sub` et `aud` correspondent **exactement** à une federated credential de l'identité.
5. **Jeton Azure.** Si tout correspond, Entra ID renvoie un **jeton d'accès** pour l'identité Azure. Le pod l'utilise pour appeler la ressource. Celle-ci applique ensuite Azure RBAC.

À aucun moment un secret à longue durée de vie n'est stocké ni transmis. La seule chose de valeur est le jeton Kubernetes. Il est de courte durée, limité à une audience, et inutilisable pour un autre compte de service.

## 3. Mise en place sur Kubernetes, cluster quelconque

Sur un cluster autogéré (kubeadm, k3s, cluster on-premise ou dans un autre cloud), c'est le **projet open source** [Azure Workload Identity](https://azure.github.io/azure-workload-identity/docs/installation.html) qui fournit le mécanisme. **Tout est à la charge de l'administrateur.**

### Composants à mettre en place

**1. Une paire de clés de signature des comptes de service.** Il faut la générer, ou réutiliser celle du cluster, puis en gérer la rotation soi-même.

**2. Un issuer OIDC public.** Il faut publier, à une URL HTTPS accessible par Entra ID, le document de découverte `/.well-known/openid-configuration` et les JWKS `/openid/v1/jwks` ([procédure](https://azure.github.io/azure-workload-identity/docs/installation/self-managed-clusters/oidc-issuer.html)). En pratique, on les héberge souvent comme fichiers statiques, par exemple dans un conteneur de stockage public. L'outil `azwi jwks` génère le JWKS à partir de la clé publique.

**3. La configuration du plan de contrôle** ([flags requis](https://azure.github.io/azure-workload-identity/docs/installation/self-managed-clusters/configurations.html)) :

```text
kube-apiserver:
  --service-account-issuer=https://<issuer-public>/
  --service-account-signing-key-file=/etc/kubernetes/pki/sa.key
  --service-account-key-file=/etc/kubernetes/pki/sa.pub
kube-controller-manager:
  --service-account-private-key-file=/etc/kubernetes/pki/sa.key
```

L'`iss` des jetons doit être exactement l'URL publiée à l'étape 2.

**4. Le webhook d'admission mutant**, installé avec Helm ([installation](https://azure.github.io/azure-workload-identity/docs/installation/mutating-admission-webhook.html)) :

```bash
helm repo add azure-workload-identity https://azure.github.io/azure-workload-identity/charts
helm repo update
helm install workload-identity-webhook azure-workload-identity/workload-identity-webhook \
  --namespace azure-workload-identity-system --create-namespace \
  --set azureTenantID="${AZURE_TENANT_ID}"
```

Il faut ensuite suivre ses mises à jour et la rotation de son certificat TLS.

**5. Côté Azure, identique à AKS** : une identité managée ou une application Entra, une federated credential pointant vers **l'issuer autogéré**, et une assignation de rôle.

**6. Côté application** : un ServiceAccount annoté, le label `azure.workload.identity/use: "true"` sur le pod, et un SDK compatible. Les versions minimales sont listées dans la documentation, par exemple `azure-identity` 1.13.0 pour Python.

## 4. Mise en place sur AKS, et ce qui change

Sur AKS, les composants 1 à 4 de la section 3 sont **fournis et gérés par la plateforme**. Deux options de cluster suffisent ([déploiement sur AKS](https://learn.microsoft.com/azure/aks/workload-identity-deploy-cluster)) :

```bash
az aks update -g <rg> -n <cluster> --enable-oidc-issuer --enable-workload-identity
az aks show  -g <rg> -n <cluster> --query "oidcIssuerProfile.issuerUrl" -o tsv
# ex. https://francecentral.oic.prod-aks.azure.com/<tenant-id>/<uuid>/
```

Pour les clusters AKS Standard **créés** en Kubernetes 1.34 ou plus, l'issuer OIDC est activé par défaut. Une fois activé, il ne peut plus être désactivé ([documentation OIDC issuer](https://learn.microsoft.com/azure/aks/use-oidc-issuer)). C'est le cas du cluster du TP, créé en 1.35 : `oidcIssuerProfile.enabled` vaut `true` sans qu'on l'ait demandé. Le webhook Workload ID, lui, n'est pas activé (`securityProfile.workloadIdentity` vaut `null`). Sans federated credential, cet issuer ne donne accès à rien dans Azure.

Ensuite, côté Azure et côté application :

```bash
az identity create -g <rg> -n <identite>
az identity federated-credential create --name <fic> --identity-name <identite> -g <rg> \
  --issuer "<issuerUrl>" \
  --subject system:serviceaccount:<namespace>:<serviceaccount> \
  --audience api://AzureADTokenExchange
az role assignment create --assignee-object-id <principalId> --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" --scope <resource-id-cible>
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: prod
  annotations:
    azure.workload.identity/client-id: "<client-id de l'identité>"
---
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: prod
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: app-sa
  containers:
    - name: app
      image: <image utilisant DefaultAzureCredential>
```

### Différences avec la section 3

| Élément | Kubernetes quelconque (projet open source) | AKS (Workload ID managé) |
|---|---|---|
| Clés de signature | Générées et tournées par l'administrateur | Gérées par AKS |
| Issuer OIDC public | À héberger soi-même (stockage statique, HTTPS) | Fourni par AKS : `https://{region}.oic.prod-aks.azure.com/{tenant}/{uuid}`, activé par `--enable-oidc-issuer` |
| Flags kube-apiserver et controller-manager | À configurer à la main | Configurés par AKS |
| Webhook mutant | Installation Helm, mises à jour à gérer | Déployé par `--enable-workload-identity`. Son certificat est tourné avec l'auto-rotation des certificats du cluster |
| Objets Azure et Kubernetes | Identité, federated credential, rôle, ServiceAccount, label | **Identiques** |
| AKS Automatic | Sans objet | OIDC issuer et Workload ID **préconfigurés** |

En résumé, le **modèle de confiance est le même**. La différence porte sur **qui opère l'issuer OIDC et le webhook** : l'administrateur du cluster dans un cas, Microsoft dans l'autre.

### Points d'attention communs

- 20 federated credentials au plus par identité managée.
- Quelques secondes de propagation après la création d'une federated credential.
- Utiliser des scopes au format `<ressource>/.default`.
- Ne pas coder en dur le chemin du jeton : lire `AZURE_FEDERATED_TOKEN_FILE`.
- Redémarrer les pods après toute modification des annotations du ServiceAccount.

## Sources

- [Use a Microsoft Entra Workload ID on AKS](https://learn.microsoft.com/azure/aks/workload-identity-overview)
- [Deploy and configure an AKS cluster with Microsoft Entra Workload ID](https://learn.microsoft.com/azure/aks/workload-identity-deploy-cluster)
- [Azure Workload Identity, installation](https://azure.github.io/azure-workload-identity/docs/installation.html)
- [Self-managed clusters : OIDC issuer](https://azure.github.io/azure-workload-identity/docs/installation/self-managed-clusters/oidc-issuer.html) et [configurations](https://azure.github.io/azure-workload-identity/docs/installation/self-managed-clusters/configurations.html)
- [Mutating admission webhook](https://azure.github.io/azure-workload-identity/docs/installation/mutating-admission-webhook.html)
