#!/bin/bash
# =============================================================================
# KUBERNETES BOOTSTRAP
# =============================================================================
# Installs Cilium CNI and ArgoCD on freshly bootstrapped Talos cluster
#
# Prerequisites:
#   - Talos cluster bootstrapped (run ./deploy.sh first)
#   - Nodes are NotReady (no CNI yet)
#
# Usage:
#   ./bootstrap.sh           - Install everything
#   ./bootstrap.sh cilium    - Install only Cilium
#   ./bootstrap.sh argocd    - Install only ArgoCD (requires Cilium)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$PROJECT_ROOT/infra"
CLUSTER_DIR="$PROJECT_ROOT/cluster"
TALOS_CONFIG_DIR="$INFRA_DIR/talos-config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}▶${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }

# Set kubeconfig
export KUBECONFIG="$TALOS_CONFIG_DIR/kubeconfig"

# =============================================================================
# INSTALL CILIUM CNI
# =============================================================================
install_cilium() {
    log "Installing Cilium CNI..."
    
    # Read config from cluster-config.yaml
    local vip=$(yq eval '.cluster.vip' "$INFRA_DIR/cluster-config.yaml")
    local cilium_version=$(yq eval '.versions.cilium' "$INFRA_DIR/cluster-config.yaml")
    
    log "VIP: $vip"
    log "Cilium version: $cilium_version"
    
    # Add Cilium Helm repo
    log "Adding Cilium Helm repository..."
    helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
    helm repo update cilium
    
    # Install Cilium using cluster/cilium configuration
    log "Installing Cilium $cilium_version..."
    kustomize build --enable-helm "$CLUSTER_DIR/cilium" | kubectl apply -f -
    
    # Clean up helm charts cache
    rm -rf "$CLUSTER_DIR/cilium/charts" 2>/dev/null || true
    
    success "Cilium installed"
    
    log "Waiting for nodes to become Ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    success "All nodes are Ready"
    
    echo ""
    kubectl get nodes -o wide
    echo ""
    
    # Apply node role labels (node-role.kubernetes.io/worker cannot be set via Talos config)
    if [ -f "$SCRIPT_DIR/label-nodes.sh" ]; then
        log "Applying worker node role labels..."
        bash "$SCRIPT_DIR/label-nodes.sh"
    fi
}

# =============================================================================
# INSTALL ARGOCD
# =============================================================================
install_argocd() {
    log "Installing ArgoCD..."
    
    # Check if Cilium is running
    if ! kubectl get pods -n kube-system -l k8s-app=cilium &>/dev/null; then
        error "Cilium not found. Install Cilium first: ./bootstrap.sh cilium"
    fi
    
    # Check for cluster manifests
    if [ ! -d "$CLUSTER_DIR/argocd" ]; then
        error "ArgoCD manifests not found in $CLUSTER_DIR/argocd"
    fi
    
    # Install using cluster/argocd configuration
    log "Applying ArgoCD manifests..."
    kustomize build --enable-helm "$CLUSTER_DIR/argocd" | kubectl apply -f -
    
    # Clean up helm charts cache
    rm -rf "$CLUSTER_DIR/argocd/charts" 2>/dev/null || true
    
    log "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
    
    success "ArgoCD installed"
    
    # Apply main ArgoCD Application (App-of-Apps pattern)
    if [ -f "$CLUSTER_DIR/main.yaml" ]; then
        log "Applying ArgoCD App-of-Apps configuration..."
        kubectl apply -f "$CLUSTER_DIR/main.yaml"
        success "App-of-Apps configured - GitOps enabled"
    else
        warn "main.yaml not found, skipping App-of-Apps setup"
    fi
    
    echo ""
    log "🔑 ArgoCD Initial Admin Password:"
    echo "-----------------------------------"
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo
    echo ""
    
    log "📝 ArgoCD Access:"
    echo "-----------------------------------"
    echo "Username: admin"
    echo "Password: (shown above)"
    echo ""
    echo "Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443  --address 0.0.0.0"
    echo "Then access: https://localhost:8080"
    echo ""
    
    log "📦 ArgoCD will now automatically deploy applications from cluster/ directory"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================
show_usage() {
    cat << EOF
Usage: $(basename "$0") [command]

Commands:
    (no args)   Install everything (Cilium + ArgoCD + optional services)
    cilium      Install only Cilium CNI
    argocd      Install only ArgoCD (requires Cilium)
    optional    Install optional services (cert-manager, ingress-nginx)

Examples:
    $(basename "$0")              # Full bootstrap
    $(basename "$0") cilium       # Just Cilium
    $(basename "$0") argocd       # Just ArgoCD

EOF
}

# Check prerequisites
if [ ! -f "$KUBECONFIG" ]; then
    error "Kubeconfig not found. Run './deploy.sh' first to bootstrap cluster"
fi

case "${1:-all}" in
    cilium)
        install_cilium
        ;;
    argocd)
        install_argocd
        ;;
    optional)
        install_optional_services
        ;;
    all)
        install_cilium
        echo ""
        install_argocd
        echo ""
        success "🎉 Bootstrap complete!"
        ;;
    -h|--help|help)
        show_usage
        ;;
    *)
        error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
