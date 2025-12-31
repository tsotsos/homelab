#!/bin/bash
# =============================================================================
# TALOS KUBERNETES COMPONENT INSTALLER
# =============================================================================
# Install core Kubernetes components on Talos bare-metal cluster
# Each component can be installed independently or all together
#
# Prerequisites:
#   - Talos cluster bootstrapped and kubeconfig available
#   - Unsealed secrets in secrets-un/ (for components requiring secrets)
#
# Usage:
#   ./install.sh --all                     - Install all components
#   ./install.sh --cilium                  - Install only Cilium
#   ./install.sh --cilium --longhorn       - Install multiple components
#   ./install.sh --labels                  - Only apply node labels
#   ./install.sh --seal-secrets            - Only seal secrets
#   ./install.sh --help                    - Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INFRA_DIR="$PROJECT_ROOT/infra"
CLUSTER_DIR="$PROJECT_ROOT/cluster"
SECRETS_UNSEALED_DIR="$PROJECT_ROOT/secrets-un"
TALOS_DIR="$INFRA_DIR/talos"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}▶${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
step() { echo -e "${CYAN}━━━ $1 ━━━${NC}"; }

# Set kubeconfig - look for it in talos directory or use default
if [ -f "$TALOS_DIR/kubeconfig" ]; then
    export KUBECONFIG="$TALOS_DIR/kubeconfig"
elif [ -f "$HOME/.kube/config" ]; then
    export KUBECONFIG="$HOME/.kube/config"
else
    error "Kubeconfig not found. Expected at $TALOS_DIR/kubeconfig or ~/.kube/config"
fi

# =============================================================================
# COMPONENT FLAGS
# =============================================================================
INSTALL_ALL=false
INSTALL_LABELS=false
INSTALL_CILIUM=false
INSTALL_KUBE_VIP=false
INSTALL_LOCAL_PATH=false
INSTALL_SEALED_SECRETS=false
INSTALL_EXTERNAL_DNS=false
INSTALL_CERT_MANAGER=false
INSTALL_LONGHORN=false
INSTALL_ARGOCD=false
SEAL_SECRETS_ONLY=false

# =============================================================================
# HELP
# =============================================================================
show_help() {
    cat << EOF
Talos Kubernetes Component Installer

Usage:
  ./install.sh [OPTIONS]

Options:
  --all                 Install all components in order
  --labels              Apply node labels from cluster-config.yaml
  --cilium              Install Cilium CNI
  --kube-vip            Install kube-vip and kube-vip-cloud-provider
  --local-path          Install local-path-provisioner for NVMe storage
  --sealed-secrets      Install sealed-secrets controller
  --external-dns        Install external-dns
  --cert-manager        Install cert-manager
  --longhorn            Install Longhorn storage
  --argocd              Install ArgoCD
  --seal-secrets        Only seal secrets (requires sealed-secrets installed)
  --help, -h            Show this help

Examples:
  # Install everything
  ./install.sh --all

  # Install only networking components
  ./install.sh --labels --cilium --kube-vip

  # Install storage and GitOps
  ./install.sh --longhorn --argocd

  # Apply labels and install CNI
  ./install.sh --labels --cilium

  # Seal all secrets
  ./install.sh --seal-secrets

Component Install Order (when using --all):
  1. Node Labels
  2. Cilium CNI
  3. kube-vip + kube-vip-cloud-provider
  4. local-path-provisioner (NVMe storage for TSDB)
  5. sealed-secrets (and seal all secrets)
  6. external-dns
  7. cert-manager
  8. Longhorn (SATA storage for apps)
  9. ArgoCD

EOF
    exit 0
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================
check_prerequisites() {
    log "Checking prerequisites..."
    
    command -v kubectl >/dev/null 2>&1 || error "kubectl not installed"
    command -v kustomize >/dev/null 2>&1 || error "kustomize not installed"
    command -v helm >/dev/null 2>&1 || error "helm not installed"
    command -v yq >/dev/null 2>&1 || error "yq not installed"
    
    if [ ! -f "$KUBECONFIG" ]; then
        error "Kubeconfig not found at $KUBECONFIG"
    fi
    
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to Kubernetes cluster. Ensure cluster is running"
    fi
    
    success "Prerequisites OK"
}

# =============================================================================
# APPLY NODE LABELS
# =============================================================================
install_node_labels() {
    step "APPLYING NODE LABELS"
    
    local config_file="$INFRA_DIR/cluster-config.yaml"
    
    if [ ! -f "$config_file" ]; then
        warn "cluster-config.yaml not found at $config_file, skipping node labels"
        return 0
    fi
    
    log "Applying node labels from cluster-config.yaml..."
    
    # Parse cluster-config.yaml and apply labels to each node
    for node in $(yq eval '.nodes | keys | .[]' "$config_file"); do
        role=$(yq eval ".nodes.\"$node\".role" "$config_file")
        
        # Apply worker role label
        if [ "$role" = "worker" ]; then
            info "Labeling node: $node"
            kubectl label node "$node" "node-role.kubernetes.io/worker=" --overwrite 2>/dev/null || true
            
            # Get all custom labels for this node
            labels=$(yq eval ".nodes.\"$node\".labels // {}" "$config_file" -o=json)
            
            # Apply each label
            echo "$labels" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' | while read -r label; do
                kubectl label node "$node" "$label" --overwrite 2>/dev/null || true
            done
        fi
    done
    
    echo ""
    kubectl get nodes --show-labels
    echo ""
    
    success "Node labels applied"
}

# =============================================================================
# INSTALL CILIUM CNI
# =============================================================================
install_cilium() {
    step "INSTALLING CILIUM CNI"
    
    if [ ! -d "$CLUSTER_DIR/network/cilium" ]; then
        error "Cilium config not found at $CLUSTER_DIR/network/cilium"
    fi
    
    # Check if already installed
    if kubectl get pods -n kube-system -l k8s-app=cilium &>/dev/null && \
       kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
        warn "Cilium already installed and running"
        return 0
    fi
    
    log "Adding Cilium Helm repository..."
    helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
    helm repo update cilium
    
    log "Installing Cilium using kustomize..."
    kustomize build --enable-helm "$CLUSTER_DIR/network/cilium" | kubectl apply -f -
    
    # Clean up generated charts
    rm -rf "$CLUSTER_DIR/network/cilium/charts" 2>/dev/null || true
    
    log "Waiting for Cilium to be ready..."
    kubectl wait --for=condition=Ready pods -l k8s-app=cilium -n kube-system --timeout=300s || true
    
    log "Waiting for nodes to become Ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s || true
    
    success "Cilium installed and operational"
    echo ""
    kubectl get nodes -o wide
    echo ""
}

# =============================================================================
# INSTALL KUBE-VIP AND KUBE-VIP-CLOUD-PROVIDER
# =============================================================================
install_kube_vip() {
    step "INSTALLING KUBE-VIP AND KUBE-VIP-CLOUD-PROVIDER"
    
    if [ ! -d "$CLUSTER_DIR/network/kube-vip" ]; then
        error "kube-vip config not found at $CLUSTER_DIR/network/kube-vip"
    fi
    
    # Install kube-vip
    log "Installing kube-vip..."
    if kubectl get daemonset -n kube-system kube-vip &>/dev/null; then
        warn "kube-vip already installed"
    else
        kustomize build --enable-helm "$CLUSTER_DIR/network/kube-vip" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/network/kube-vip/charts" 2>/dev/null || true
        
        log "Waiting for kube-vip to be ready..."
        kubectl rollout status daemonset kube-vip -n kube-system --timeout=120s || true
        success "kube-vip installed"
    fi
    
    # Install kube-vip-cloud-provider
    if [ ! -d "$CLUSTER_DIR/network/kube-vip-cloud-provider" ]; then
        warn "kube-vip-cloud-provider config not found, skipping"
        return 0
    fi
    
    log "Installing kube-vip-cloud-provider..."
    if kubectl get deployment -n kube-system kube-vip-cloud-provider &>/dev/null; then
        warn "kube-vip-cloud-provider already installed"
    else
        kustomize build --enable-helm "$CLUSTER_DIR/network/kube-vip-cloud-provider" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/network/kube-vip-cloud-provider/charts" 2>/dev/null || true
        
        log "Waiting for kube-vip-cloud-provider to be ready..."
        kubectl rollout status deployment kube-vip-cloud-provider -n kube-system --timeout=120s || true
        success "kube-vip-cloud-provider installed"
    fi
}

# =============================================================================
# INSTALL LOCAL-PATH-PROVISIONER (NVMe Storage for TSDB)
# =============================================================================
install_local_path() {
    step "INSTALLING LOCAL-PATH-PROVISIONER"
    
    # Check if already installed
    if kubectl get storageclass local-path-nvme &>/dev/null; then
        warn "local-path-nvme StorageClass already exists"
        return 0
    fi
    
    log "Installing local-path-provisioner..."
    
    # Create namespace
    kubectl create namespace local-path-storage 2>/dev/null || true
    
    # Install local-path-provisioner
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
    
    log "Waiting for local-path-provisioner to be ready..."
    kubectl wait --for=condition=Ready pods -l app=local-path-provisioner -n local-path-storage --timeout=120s || true
    
    # Create custom StorageClass for NVMe (with custom name)
    log "Creating local-path-nvme StorageClass..."
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path-nvme
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
EOF
    
    success "local-path-provisioner installed with local-path-nvme StorageClass"
    echo ""
    kubectl get storageclass
    echo ""
}

# =============================================================================
# INSTALL SEALED-SECRETS
# =============================================================================
install_sealed_secrets() {
    step "INSTALLING SEALED-SECRETS"
    
    if [ ! -d "$CLUSTER_DIR/security/sealed-secrets" ]; then
        error "sealed-secrets config not found at $CLUSTER_DIR/security/sealed-secrets"
    fi
    
    # Install sealed-secrets controller
    log "Installing sealed-secrets controller..."
    if kubectl get deployment -n kube-system sealed-secrets &>/dev/null; then
        warn "sealed-secrets already installed"
    else
        kustomize build --enable-helm "$CLUSTER_DIR/security/sealed-secrets" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/security/sealed-secrets/charts" 2>/dev/null || true
        
        log "Waiting for sealed-secrets to be ready..."
        kubectl rollout status deployment sealed-secrets -n kube-system --timeout=120s || true
    fi
    
    # Wait a bit for the controller to fully initialize
    sleep 5
    
    success "sealed-secrets controller installed"
    
    # Check if kubeseal is available and seal secrets
    if command -v kubeseal >/dev/null 2>&1; then
        seal_all_secrets
    else
        warn "kubeseal not installed, skipping secret sealing"
        info "Install kubeseal and run: ./install-components.sh --seal-secrets"
    fi
}

# =============================================================================
# SEAL ALL SECRETS FUNCTION
# =============================================================================
seal_all_secrets() {
    log "Sealing all secrets in $SECRETS_UNSEALED_DIR..."
    
    if [ ! -d "$SECRETS_UNSEALED_DIR" ]; then
        warn "Unsealed secrets directory not found: $SECRETS_UNSEALED_DIR"
        return 0
    fi
    
    # Find all yaml files in secrets-un directory (excluding temp files)
    local secret_files=$(find "$SECRETS_UNSEALED_DIR" -maxdepth 1 -name "*.yaml" -type f ! -name "*-tmp-*")
    
    if [ -z "$secret_files" ]; then
        warn "No unsealed secrets found in $SECRETS_UNSEALED_DIR"
        return 0
    fi
    
    local sealed_count=0
    local failed_count=0
    
    for secret_file in $secret_files; do
        local filename=$(basename "$secret_file")
        local secret_name="${filename%.yaml}"
        
        info "Processing: $filename"
        
        # Extract namespace from the secret file
        local namespace=$(yq eval '.metadata.namespace' "$secret_file")
        
        if [ "$namespace" = "null" ] || [ -z "$namespace" ]; then
            warn "Skipping $filename - no namespace defined"
            ((failed_count++))
            continue
        fi
        
        # Find matching directory by searching for a directory with the same name as the secret file
        # Pattern: cluster/*/$secret_name/
        local target_dir=$(find "$CLUSTER_DIR" -type d -name "$secret_name" | head -n 1)
        
        if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
            warn "Cannot find target directory matching: cluster/*/$secret_name/"
            warn "  Expected directory: cluster/<category>/$secret_name/"
            warn "  Secret file: $filename (namespace: $namespace)"
            ((failed_count++))
            continue
        fi
        
        local output_file="$target_dir/sealed-secret.yaml"
        
        log "Sealing $filename -> $(echo $output_file | sed "s|$PROJECT_ROOT/||")"
        
        # Seal the secret using kubeseal (accessing the cluster directly)
        if kubeseal --controller-name sealed-secrets --controller-namespace kube-system --format yaml < "$secret_file" > "$output_file" 2>/dev/null; then
            # Remove all creationTimestamp fields recursively
            yq eval 'del(.. | select(has("creationTimestamp")).creationTimestamp)' -i "$output_file"
            
            success "Sealed: $filename -> $(basename "$(dirname "$target_dir")")/$(basename "$target_dir")/sealed-secret.yaml"
            ((sealed_count++))
        else
            error "Failed to seal $filename"
            ((failed_count++))
        fi
    done
    
    echo ""
    if [ $sealed_count -gt 0 ]; then
        success "Sealed $sealed_count secret(s)"
    fi
    if [ $failed_count -gt 0 ]; then
        warn "Failed or skipped $failed_count secret(s)"
    fi
}

# =============================================================================
# INSTALL EXTERNAL-DNS
# =============================================================================
install_external_dns() {
    step "INSTALLING EXTERNAL-DNS"
    
    if [ ! -d "$CLUSTER_DIR/network/external-dns" ]; then
        error "external-dns config not found at $CLUSTER_DIR/network/external-dns"
    fi
    
    if kubectl get deployment -n external-dns external-dns-unifi &>/dev/null; then
        warn "external-dns already installed"
    else
        log "Installing external-dns..."
        kustomize build --enable-helm "$CLUSTER_DIR/network/external-dns" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/network/external-dns/charts" 2>/dev/null || true
        
        log "Waiting for external-dns to be ready..."
        kubectl rollout status deployment external-dns-unifi -n external-dns --timeout=120s || true
        success "external-dns installed"
    fi
}

# =============================================================================
# INSTALL CERT-MANAGER
# =============================================================================
install_cert_manager() {
    step "INSTALLING CERT-MANAGER"
    
    if [ ! -d "$CLUSTER_DIR/security/cert-manager" ]; then
        error "cert-manager config not found at $CLUSTER_DIR/security/cert-manager"
    fi
    
    if kubectl get deployment -n cert-manager cert-manager &>/dev/null; then
        warn "cert-manager already installed"
    else
        log "Installing cert-manager..."
        kustomize build --enable-helm "$CLUSTER_DIR/security/cert-manager" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/security/cert-manager/charts" 2>/dev/null || true
        
        log "Waiting for cert-manager to be ready..."
        kubectl rollout status deployment cert-manager -n cert-manager --timeout=180s || true
        kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=180s || true
        kubectl rollout status deployment cert-manager-cainjector -n cert-manager --timeout=180s || true
        
        # Wait for webhook to be fully functional and CRDs to be ready
        log "Waiting for cert-manager CRDs and webhook to be ready..."
        sleep 15
        kubectl wait --for=condition=Established crd/clusterissuers.cert-manager.io --timeout=60s || true
        
        if [ -f "$CLUSTER_DIR/security/cert-manager/clusterIssuer.yaml" ]; then
            log "Applying ClusterIssuer..."
            kubectl apply -f "$CLUSTER_DIR/security/cert-manager/clusterIssuer.yaml"
        fi
        
        success "cert-manager installed"
    fi
}

# =============================================================================
# INSTALL LONGHORN
# =============================================================================
install_longhorn() {
    step "INSTALLING LONGHORN"
    
    if [ ! -d "$CLUSTER_DIR/storage/longhorn" ]; then
        error "Longhorn config not found at $CLUSTER_DIR/storage/longhorn"
    fi
    
    if kubectl get namespace longhorn-system &>/dev/null; then
        warn "Longhorn already installed"
    else
        log "Installing Longhorn..."
        kustomize build --enable-helm "$CLUSTER_DIR/storage/longhorn" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/storage/longhorn/charts" 2>/dev/null || true
        
        log "Waiting for Longhorn to be ready (this may take a few minutes)..."
        kubectl wait --for=condition=Ready pods -l app=longhorn-manager -n longhorn-system --timeout=300s || true
        success "Longhorn installed"
    fi
}

# =============================================================================
# INSTALL ARGOCD
# =============================================================================
install_argocd() {
    step "INSTALLING ARGOCD"
    
    if [ ! -d "$CLUSTER_DIR/argocd" ]; then
        error "ArgoCD config not found at $CLUSTER_DIR/argocd"
    fi
    
    if kubectl get namespace argocd &>/dev/null; then
        warn "ArgoCD already installed"
    else
        # Create namespace first
        log "Creating ArgoCD namespace..."
        kubectl create namespace argocd
        
        log "Installing ArgoCD..."
        kustomize build --enable-helm "$CLUSTER_DIR/argocd" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/argocd/charts" 2>/dev/null || true
        
        log "Waiting for ArgoCD to be ready..."
        kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s || true
    fi
    
    # Get ArgoCD admin password
    log "Retrieving ArgoCD admin password..."
    local password=""
    for i in {1..30}; do
        password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")
        if [ -n "$password" ]; then
            break
        fi
        sleep 2
    done
    
    if [ -z "$password" ]; then
        warn "Could not retrieve ArgoCD password automatically"
        info "Run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
    else
        echo ""
        success "ArgoCD installed successfully!"
        echo ""
        info "ArgoCD Admin Credentials:"
        echo "  Username: admin"
        echo "  Password: $password"
        echo ""
        info "Access ArgoCD:"
        echo "  Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
        echo "  Then visit: https://localhost:8080"
        echo ""
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    # Parse arguments
    if [ $# -eq 0 ]; then
        show_help
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                INSTALL_ALL=true
                shift
                ;;
            --labels)
                INSTALL_LABELS=true
                shift
                ;;
            --cilium)
                INSTALL_CILIUM=true
                shift
                ;;
            --kube-vip)
                INSTALL_KUBE_VIP=true
                shift
                ;;
            --local-path)
                INSTALL_LOCAL_PATH=true
                shift
                ;;
            --sealed-secrets)
                INSTALL_SEALED_SECRETS=true
                shift
                ;;
            --external-dns)
                INSTALL_EXTERNAL_DNS=true
                shift
                ;;
            --cert-manager)
                INSTALL_CERT_MANAGER=true
                shift
                ;;
            --longhorn)
                INSTALL_LONGHORN=true
                shift
                ;;
            --argocd)
                INSTALL_ARGOCD=true
                shift
                ;;
            --seal-secrets)
                SEAL_SECRETS_ONLY=true
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                error "Unknown option: $1. Use --help for usage."
                ;;
        esac
    done
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         TALOS KUBERNETES COMPONENT INSTALLER               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    
    # If only sealing secrets
    if [ "$SEAL_SECRETS_ONLY" = true ]; then
        if ! kubectl get deployment -n kube-system sealed-secrets &>/dev/null; then
            error "sealed-secrets controller not installed. Install it first with: ./install.sh --sealed-secrets"
        fi
        if ! command -v kubeseal >/dev/null 2>&1; then
            error "kubeseal command not found. Install kubeseal first."
        fi
        seal_all_secrets
        success "Secret sealing completed"
        exit 0
    fi
    
    # Execute selected components
    if [ "$INSTALL_ALL" = true ]; then
        INSTALL_LABELS=true
        INSTALL_CILIUM=true
        INSTALL_KUBE_VIP=true
        INSTALL_LOCAL_PATH=true
        INSTALL_SEALED_SECRETS=true
        INSTALL_EXTERNAL_DNS=true
        INSTALL_CERT_MANAGER=true
        INSTALL_LONGHORN=true
        INSTALL_ARGOCD=true
    fi
    
    # Install in order
    if [ "$INSTALL_LABELS" = true ]; then install_node_labels; fi
    if [ "$INSTALL_CILIUM" = true ]; then install_cilium; fi
    if [ "$INSTALL_KUBE_VIP" = true ]; then install_kube_vip; fi
    if [ "$INSTALL_LOCAL_PATH" = true ]; then install_local_path; fi
    if [ "$INSTALL_SEALED_SECRETS" = true ]; then install_sealed_secrets; fi
    if [ "$INSTALL_EXTERNAL_DNS" = true ]; then install_external_dns; fi
    if [ "$INSTALL_CERT_MANAGER" = true ]; then install_cert_manager; fi
    if [ "$INSTALL_LONGHORN" = true ]; then install_longhorn; fi
    if [ "$INSTALL_ARGOCD" = true ]; then install_argocd; fi
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         INSTALLATION COMPLETED SUCCESSFULLY! 🎉            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    success "Selected components installed"
    info "Verify installation:"
    echo "  kubectl get pods -A"
    echo "  kubectl get nodes -o wide"
    echo ""
}

# Run main function
main "$@"
