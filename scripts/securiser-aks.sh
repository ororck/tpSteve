#!/usr/bin/env bash
# Applique le plan de sécurisation AKS sur un cluster existant, étape par étape.
# Idempotent : chaque étape lit l'état courant et ne rejoue que ce qui manque.
# Ne supprime jamais d'assignation de rôle.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage : securiser-aks.sh --cluster <nom|resource-id> [--resource-group <rg>]
                         --admins-group-id <object-id> --readers-group-id <object-id>
                         [--ip-range <CIDR>] [--manifests-dir <dossier>] [--dry-run]

  --cluster           Nom du cluster (avec --resource-group) ou resource ID complet.
  --admins-group-id   Object ID du groupe Entra qui reçoit "Azure Kubernetes Service RBAC Cluster Admin".
  --readers-group-id  Object ID du groupe Entra qui reçoit "Azure Kubernetes Service RBAC Reader".
  --ip-range          Plage autorisée sur le serveur d'API (adresse réseau CIDR).
                      Sans cette option, aucune restriction de plages n'est appliquée.
  --manifests-dir     Dossier contenant o7-namespace-prod.yaml, o7-resourcequota.yaml, o7-limitrange.yaml.
  --dry-run           Affiche les écritures sans les exécuter. Les lectures sont exécutées.
EOF
}

CLUSTER=""
RG=""
ADMINS_GROUP_ID=""
READERS_GROUP_ID=""
IP_RANGE=""
MANIFESTS_DIR="$(cd "$(dirname "$0")/.." && pwd)/manifests"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster) CLUSTER="$2"; shift 2 ;;
    --resource-group) RG="$2"; shift 2 ;;
    --admins-group-id) ADMINS_GROUP_ID="$2"; shift 2 ;;
    --readers-group-id) READERS_GROUP_ID="$2"; shift 2 ;;
    --ip-range) IP_RANGE="$2"; shift 2 ;;
    --manifests-dir) MANIFESTS_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$CLUSTER" || -z "$ADMINS_GROUP_ID" || -z "$READERS_GROUP_ID" ]]; then
  usage >&2
  exit 2
fi

if [[ -n "$IP_RANGE" ]] && ! python3 -c "import ipaddress,sys; ipaddress.ip_network(sys.argv[1], strict=True)" "$IP_RANGE" 2>/dev/null; then
  echo "Plage invalide ou pas une adresse réseau (bits d'hôte non nuls) : $IP_RANGE" >&2
  exit 2
fi

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# Toute écriture passe par cette fonction, pour que --dry-run n'exécute rien.
write() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
KCFG="$TMP_DIR/kubeconfig"

# Étape 0 : résolution du cluster
if [[ "$CLUSTER" == /subscriptions/* ]]; then
  # Format : /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<nom>
  IFS=/ read -r -a ID_PARTS <<< "$CLUSTER"
  if [[ ${#ID_PARTS[@]} -ne 9 || "${ID_PARTS[7],,}" != "managedclusters" ]]; then
    echo "Resource ID de cluster AKS invalide : $CLUSTER" >&2
    exit 2
  fi
  az account set --subscription "${ID_PARTS[2]}"
  RG="${ID_PARTS[4]}"
  NAME="${ID_PARTS[8]}"
  AKS_ID="$(az aks show -g "$RG" -n "$NAME" --query id -o tsv)"
else
  if [[ -z "$RG" ]]; then
    echo "--resource-group est obligatoire avec un nom de cluster." >&2
    exit 2
  fi
  NAME="$CLUSTER"
  AKS_ID="$(az aks show -g "$RG" -n "$NAME" --query id -o tsv)"
fi
log "Cluster : $AKS_ID"

aks_query() { az aks show -g "$RG" -n "$NAME" --query "$1" -o tsv; }

# Vérifie qu'un accès Entra non administrateur aboutit (kubeconfig utilisateur converti par kubelogin).
entra_access_ok() {
  az aks get-credentials -g "$RG" -n "$NAME" --file "$KCFG" --overwrite-existing >/dev/null 2>&1 || return 1
  KUBECONFIG="$KCFG" kubelogin convert-kubeconfig -l azurecli >/dev/null 2>&1 || return 1
  KUBECONFIG="$KCFG" kubectl get namespaces --request-timeout=20s >/dev/null 2>&1
}

# Étape 1 : intégration Entra managée et Azure RBAC (O3), jamais aad-admin-group-object-ids
AAD_MANAGED="$(aks_query "aadProfile.managed")"
AZ_RBAC="$(aks_query "aadProfile.enableAzureRbac")"
if [[ "$AAD_MANAGED" == "true" && "$AZ_RBAC" == "true" ]]; then
  log "Étape 1 : intégration Entra et Azure RBAC déjà actives, rien à rejouer."
elif [[ "$AAD_MANAGED" == "true" ]]; then
  log "Étape 1 : Entra actif, activation d'Azure RBAC."
  write az aks update -g "$RG" -n "$NAME" --enable-azure-rbac -o none
else
  log "Étape 1 : activation de l'intégration Entra (IRRÉVERSIBLE) et d'Azure RBAC."
  write az aks update -g "$RG" -n "$NAME" --enable-aad --enable-azure-rbac -o none
fi

# Étape 2 : assignations de rôles à la portée du cluster (O6), création seulement
ensure_role() {
  local group_id="$1" role="$2" existing
  existing="$(az role assignment list --assignee "$group_id" --scope "$AKS_ID" --role "$role" --query "length(@)" -o tsv)"
  if [[ "$existing" -gt 0 ]]; then
    log "Étape 2 : '$role' déjà assigné à $group_id."
  else
    log "Étape 2 : assignation de '$role' à $group_id."
    write az role assignment create --role "$role" --assignee-object-id "$group_id" \
      --assignee-principal-type Group --scope "$AKS_ID" -o none
  fi
}
ensure_role "$ADMINS_GROUP_ID" "Azure Kubernetes Service RBAC Cluster Admin"
ensure_role "$READERS_GROUP_ID" "Azure Kubernetes Service RBAC Reader"

# Étape 3 : comptes locaux (O6), refusée sans accès Entra non administrateur vérifié
if [[ "$(aks_query "disableLocalAccounts")" == "true" ]]; then
  log "Étape 3 : comptes locaux déjà désactivés."
elif [[ "$DRY_RUN" == true ]]; then
  log "Étape 3 : [dry-run] l'accès Entra serait vérifié avant de désactiver les comptes locaux."
  write az aks update -g "$RG" -n "$NAME" --disable-local-accounts -o none
elif entra_access_ok; then
  log "Étape 3 : accès Entra non administrateur vérifié, désactivation des comptes locaux."
  write az aks update -g "$RG" -n "$NAME" --disable-local-accounts -o none
  log "Étape 3 : penser à la rotation des certificats si des comptes locaux ont été utilisés (az aks rotate-certs)."
else
  log "Étape 3 : REFUS. Aucun accès Entra non administrateur n'aboutit (propagation des rôles jusqu'à 5 min ?). Comptes locaux laissés actifs."
  exit 1
fi

# Étape 4 : namespace prod et limitation de ressources (O7)
for f in o7-namespace-prod.yaml o7-resourcequota.yaml o7-limitrange.yaml; do
  if [[ ! -f "$MANIFESTS_DIR/$f" ]]; then
    echo "Manifeste manquant : $MANIFESTS_DIR/$f" >&2
    exit 1
  fi
done
if [[ "$DRY_RUN" == true ]]; then
  log "Étape 4 : [dry-run] application du namespace, du quota et du limitrange."
  write kubectl apply -f "$MANIFESTS_DIR/o7-namespace-prod.yaml" -f "$MANIFESTS_DIR/o7-resourcequota.yaml" -f "$MANIFESTS_DIR/o7-limitrange.yaml"
elif entra_access_ok; then
  log "Étape 4 : application du namespace, du quota et du limitrange (kubectl apply est idempotent)."
  KUBECONFIG="$KCFG" kubectl apply -f "$MANIFESTS_DIR/o7-namespace-prod.yaml"
  KUBECONFIG="$KCFG" kubectl apply -f "$MANIFESTS_DIR/o7-resourcequota.yaml" -f "$MANIFESTS_DIR/o7-limitrange.yaml"
else
  log "Étape 4 : accès Entra indisponible, étape ignorée."
fi

# Étape 5 : plages IP autorisées (O2), uniquement si une plage est fournie
if [[ -z "$IP_RANGE" ]]; then
  log "Étape 5 : aucune plage fournie, aucune restriction appliquée."
  exit 0
fi

if command -v dig >/dev/null 2>&1; then
  CURRENT_IP="$(dig +short "myip.opendns.com" "@resolver1.opendns.com")"
else
  CURRENT_IP="$(curl -fsS https://ipinfo.io/ip)"
fi
if ! python3 -c "import ipaddress,sys; ipaddress.ip_address(sys.argv[1])" "$CURRENT_IP" 2>/dev/null; then
  echo "Impossible de déterminer l'IP publique courante." >&2
  exit 1
fi
EGRESS_IPS=()
while IFS= read -r ip_id; do
  [[ -n "$ip_id" ]] && EGRESS_IPS+=("$(az network public-ip show --ids "$ip_id" --query ipAddress -o tsv)/32")
done < <(aks_query "networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id")

join() { local IFS=,; echo "$*"; }
FINAL_RANGES="$(join "$IP_RANGE" "${EGRESS_IPS[@]}")"
TEMP_RANGES="$(join "$IP_RANGE" "${EGRESS_IPS[@]}" "$CURRENT_IP/32")"
CURRENT_RANGES="$(aks_query "join(',', apiServerAccessProfile.authorizedIpRanges || \`[]\`)")"

if [[ "$CURRENT_RANGES" == "$FINAL_RANGES" ]]; then
  log "Étape 5 : plages déjà appliquées ($FINAL_RANGES)."
  exit 0
fi

log "Étape 5, phase 1 : plage + IP de sortie + IP courante temporaire ($TEMP_RANGES)."
write az aks update -g "$RG" -n "$NAME" --api-server-authorized-ip-ranges "$TEMP_RANGES" -o none
if [[ "$DRY_RUN" == true ]]; then
  log "Étape 5 : [dry-run] attente de 120 s, test d'accès, puis retrait de l'IP courante."
  write az aks update -g "$RG" -n "$NAME" --api-server-authorized-ip-ranges "$FINAL_RANGES" -o none
  exit 0
fi

log "Étape 5 : attente de la propagation (120 s)."
sleep 120
if ! entra_access_ok; then
  log "Étape 5 : l'accès échoue après la phase 1. Phase 2 annulée. Retour arrière possible depuis n'importe quelle IP :"
  log "  az aks update -g $RG -n $NAME --api-server-authorized-ip-ranges \"\""
  exit 1
fi

log "Étape 5, phase 2 : retrait de l'IP courante ($FINAL_RANGES)."
write az aks update -g "$RG" -n "$NAME" --api-server-authorized-ip-ranges "$FINAL_RANGES" -o none
log "Étape 5 : attendre 2 minutes puis vérifier l'accès depuis la plage autorisée."
