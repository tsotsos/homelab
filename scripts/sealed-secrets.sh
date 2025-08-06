#!/bin/bash
set -e

CLUSTER=""
MODE="all"
CLUSTERS_ROOT="../clusters"

print_usage() {
  echo ""
  echo "Usage:"
  echo "  $0 --cluster <cluster-name> [--mode all|install|seal]"
  echo ""
  echo "Options:"
  echo "  --cluster   Cluster folder name under ../clusters (e.g. s01)"
  echo "  --mode      all (default), install (only install Sealed Secrets), seal (only seal secrets)"
  echo ""
  echo "Examples:"
  echo "  $0 --cluster s01"
  echo "  $0 --cluster management --mode seal"
  echo ""
  exit 1
}

# -- Parse Args --
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      CLUSTER="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    *)
      echo "❌ Unknown option: $1"
      print_usage
      ;;
  esac
done

if [[ -z "$CLUSTER" ]]; then
  echo "❌ Missing required argument: --cluster"
  print_usage
fi

CLUSTER_PATH="${CLUSTERS_ROOT}/${CLUSTER}"

if [[ ! -d "$CLUSTER_PATH" ]]; then
  echo "❌ Cluster path not found: $CLUSTER_PATH"
  exit 1
fi

# -- Function: Install Sealed Secrets --
install_sealed_secrets() {
  echo "🔐 Installing Sealed Secrets in namespace kube-system..."
  kubectl create ns kube-system || true

  helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
  helm repo update

  helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
    --namespace kube-system

  echo "⏳ Waiting for sealed-secrets deployment to be ready..."
  kubectl rollout status deployment sealed-secrets -n kube-system --timeout=120s
}

# -- Function: Seal All unsealed-* files in Cluster Path --
seal_all_secrets() {
  echo "📄 Sealing unsealed secrets under: $CLUSTER_PATH"

  find "$CLUSTER_PATH" -type f -name "unsealed-*" | while read -r file; do
    dir=$(dirname "$file")
    base=$(basename "$file")
    sealed_file="${dir}/sealed-${base#unsealed-}"

    echo "🔐 Sealing: $file → $sealed_file"

    kubeseal --controller-name=sealed-secrets \
             --controller-namespace=kube-system \
             --format=yaml < "$file" > "$sealed_file"

  done

  echo "✅ All unsealed secrets sealed."
}

# -- Main Dispatcher --
case "$MODE" in
  all)
    install_sealed_secrets
    seal_all_secrets
    ;;
  install)
    install_sealed_secrets
    ;;
  seal)
    seal_all_secrets
    ;;
  *)
    echo "❌ Invalid mode: $MODE"
    print_usage
    ;;
esac
