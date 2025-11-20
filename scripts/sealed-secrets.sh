#!/bin/bash
set -e

MODE="all"
SEALED_SECRETS_NS="kube-system"
SEALED_SECRETS_VERSION="2.17.9"
UNSEALED_DIR="../secrets-un"
CLUSTER_DIR="../cluster"

# Function to get sealed path for a given unsealed file
get_sealed_path() {
  case "$1" in
    "cert-manager.yaml")
      echo "cert-manager/sealed-secret.yaml"
      ;;
    "external-dns.yaml")
      echo "external-dns/sealed-secret.yaml"
      ;;
    *)
      echo ""
      ;;
  esac
}

# Function to get expected namespace
get_expected_namespace() {
  case "$1" in
    "cert-manager.yaml")
      echo "cert-manager"
      ;;
    "external-dns.yaml")
      echo "external-dns"
      ;;
    *)
      echo ""
      ;;
  esac
}

# Function to get expected name
get_expected_name() {
  case "$1" in
    "cert-manager.yaml")
      echo "cloudflare-api-token-secret"
      ;;
    "external-dns.yaml")
      echo "external-dns-unifi-secret"
      ;;
    *)
      echo ""
      ;;
  esac
}

# List of secrets to process
SECRETS_TO_SEAL=("cert-manager.yaml" "external-dns.yaml")

print_usage() {
  echo ""
  echo "Usage:"
  echo "  $0 [all|install|seal|unseal|validate]"
  echo ""
  echo "Commands:"
  echo "  all         Install Sealed Secrets controller and seal all secrets (default)"
  echo "  install     Only install Sealed Secrets controller"
  echo "  seal        Only seal unsealed secrets (validates first)"
  echo "  unseal      Decrypt sealed secrets back to YAML"
  echo "  validate    Check unsealed secrets format"
  echo ""
  echo "Examples:"
  echo "  $0 all       # Install and seal all secrets"
  echo "  $0 seal      # Only seal unsealed secrets"
  echo "  $0 validate  # Validate unsealed secrets before sealing"
  echo ""
  exit 1
}

# -- Parse Args --
if [[ $# -gt 0 ]]; then
  case "$1" in
    all|install|seal|unseal|validate)
      MODE="$1"
      ;;
    *)
      echo "❌ Unknown command: $1"
      print_usage
      ;;
  esac
fi

# -- Function: Validate unsealed secrets --
validate_unsealed_secrets() {
  echo "🔍 Validating unsealed secrets format..."
  
  local has_errors=0
  
  for source_file in "${SECRETS_TO_SEAL[@]}"; do
    unsealed_path="${UNSEALED_DIR}/${source_file}"
    
    if [[ ! -f "$unsealed_path" ]]; then
      echo "⚠️  Unsealed secret not found: $unsealed_path"
      continue
    fi
    
    local actual_namespace=$(grep "namespace:" "$unsealed_path" | head -1 | awk '{print $2}')
    local actual_name=$(grep "name:" "$unsealed_path" | head -1 | awk '{print $2}')
    local expected_namespace=$(get_expected_namespace "$source_file")
    local expected_name=$(get_expected_name "$source_file")
    
    echo ""
    echo "📄 Checking: $source_file"
    echo "   Name: $actual_name (expected: $expected_name)"
    echo "   Namespace: $actual_namespace (expected: $expected_namespace)"
    
    if [[ "$actual_namespace" != "$expected_namespace" ]]; then
      echo "   ❌ NAMESPACE MISMATCH!"
      has_errors=1
    fi
    
    if [[ "$actual_name" != "$expected_name" ]]; then
      echo "   ❌ NAME MISMATCH!"
      has_errors=1
    fi
    
    if [[ "$actual_namespace" == "$expected_namespace" ]] && [[ "$actual_name" == "$expected_name" ]]; then
      echo "   ✅ Valid"
    fi
  done
  
  if [[ $has_errors -eq 1 ]]; then
    echo ""
    echo "❌ Validation failed! Please fix the unsealed secrets before sealing."
    echo ""
    echo "Fix namespace and name in secrets-un/ files to match the expected values above."
    return 1
  fi
  
  echo ""
  echo "✅ All unsealed secrets are valid!"
}

# -- Function: Install Sealed Secrets --
install_sealed_secrets() {
  echo "🔐 Installing Sealed Secrets v${SEALED_SECRETS_VERSION} in namespace $SEALED_SECRETS_NS..."
  kubectl create ns $SEALED_SECRETS_NS 2>/dev/null || true

  helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
  helm repo update

  helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
    --namespace $SEALED_SECRETS_NS \
    --version $SEALED_SECRETS_VERSION \
    --wait

  echo "⏳ Waiting for sealed-secrets deployment to be ready..."
  kubectl rollout status deployment sealed-secrets -n $SEALED_SECRETS_NS --timeout=120s
  
  echo "✅ Sealed Secrets v${SEALED_SECRETS_VERSION} installed successfully"
}

# -- Function: Seal All unsealed secrets --
seal_all_secrets() {
  echo "📄 Sealing unsealed secrets from: $UNSEALED_DIR"

  if [[ ! -d "$UNSEALED_DIR" ]]; then
    echo "❌ Unsealed secrets directory not found: $UNSEALED_DIR"
    exit 1
  fi

  # Validate before sealing
  echo "🔍 Running pre-seal validation..."
  if ! validate_unsealed_secrets; then
    exit 1
  fi
  
  echo ""
  echo "🔐 Starting sealing process..."

  # Seal mapped secrets to cluster/* directories
  for source_file in "${SECRETS_TO_SEAL[@]}"; do
    unsealed_path="${UNSEALED_DIR}/${source_file}"
    sealed_path="${CLUSTER_DIR}/$(get_sealed_path "$source_file")"
    
    if [[ ! -f "$unsealed_path" ]]; then
      echo "⚠️  Unsealed secret not found: $unsealed_path (skipping)"
      continue
    fi
    
    echo "🔐 Sealing: $unsealed_path → $sealed_path"
    
    # Ensure target directory exists
    mkdir -p "$(dirname "$sealed_path")"

    kubeseal \
      --controller-name=sealed-secrets \
      --controller-namespace=$SEALED_SECRETS_NS \
      --format=yaml < "$unsealed_path" > "$sealed_path"
  done

  echo "✅ All mapped secrets sealed to cluster/* directories."
}

# -- Function: Unseal (decrypt) sealed secrets --
unseal_all_secrets() {
  echo "📄 Unsealing sealed secrets from cluster/* directories"

  if [[ ! -d "$CLUSTER_DIR" ]]; then
    echo "❌ Cluster directory not found: $CLUSTER_DIR"
    exit 1
  fi

  mkdir -p "$UNSEALED_DIR"

  # Unseal mapped secrets from cluster/* directories
  for source_file in "${SECRETS_TO_SEAL[@]}"; do
    sealed_path="${CLUSTER_DIR}/$(get_sealed_path "$source_file")"
    unsealed_path="${UNSEALED_DIR}/${source_file}"
    
    if [[ ! -f "$sealed_path" ]]; then
      echo "⚠️  Sealed secret not found: $sealed_path (skipping)"
      continue
    fi
    
    echo "🔓 Unsealing: $sealed_path → $unsealed_path"

    # Extract the secret from the SealedSecret (this requires the secret to be deployed)
    kubectl get -f "$sealed_path" -o json 2>/dev/null | \
      jq -r '.spec.template' > "$unsealed_path" || \
      echo "⚠️  Could not unseal $sealed_path (may need to be applied to cluster first)"
  done

  echo "✅ All sealed secrets unsealed (where possible)."
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
  validate)
    validate_unsealed_secrets
    ;;
  unseal)
    unseal_all_secrets
    ;;
  *)
    echo "❌ Invalid mode: $MODE"
    print_usage
    ;;
esac
