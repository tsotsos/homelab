#!/bin/bash
# =============================================================================
# TALOS CLUSTER DEPLOYMENT
# =============================================================================
# Simple Talos deployment using Terraform-generated configurations
# No CNI - bootstraps cluster only, ready for Cilium installation
#
# Usage:
#   ./deploy.sh              - Full deployment (apply + bootstrap)
#   ./deploy.sh apply        - Apply Talos configs to nodes
#   ./deploy.sh bootstrap    - Bootstrap Kubernetes cluster
#   ./deploy.sh status       - Check cluster status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$PROJECT_ROOT/infra"
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

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================
check_prerequisites() {
    log "Checking prerequisites..."
    
    if [ ! -f "$TALOS_CONFIG_DIR/talosconfig" ]; then
        error "Talos config not found. Run 'terraform apply' in infra/ first"
    fi
    
    if [ ! -d "$TALOS_CONFIG_DIR" ] || [ ! -f "$TALOS_CONFIG_DIR/controlplane-kng-cp-1.yaml" ]; then
        error "Terraform configs not generated. Run 'terraform apply' in infra/ first"
    fi
    
    command -v talosctl >/dev/null 2>&1 || error "talosctl not installed"
    command -v kubectl >/dev/null 2>&1 || error "kubectl not installed"
    command -v terraform >/dev/null 2>&1 || error "terraform not installed"
    
    success "Prerequisites OK"
}

# =============================================================================
# APPLY - Apply Talos Configurations to Nodes
# =============================================================================
cmd_apply() {
    log "Applying Talos configurations to nodes..."
    check_prerequisites
    
    cd "$INFRA_DIR"
    
    # Get all nodes from Terraform
    local cp_nodes=$(terraform output -json control_plane_nodes 2>/dev/null | jq -r 'to_entries[] | @base64')
    local worker_nodes=$(terraform output -json worker_nodes 2>/dev/null | jq -r 'to_entries[] | @base64')
    
    # Apply to control plane nodes
    for node_data in $cp_nodes; do
        local node=$(echo "$node_data" | base64 --decode)
        local name=$(echo "$node" | jq -r '.key')
        local ip=$(echo "$node" | jq -r '.value.ip_address')
        local config="$TALOS_CONFIG_DIR/controlplane-${name}.yaml"
        
        log "Applying config to $name ($ip)..."
        if talosctl apply-config \
            --talosconfig "$TALOS_CONFIG_DIR/talosconfig" \
            --nodes "$ip" \
            --file "$config" \
            --insecure; then
            success "Config applied to $name"
        else
            warn "Failed to apply config to $name (may already be configured)"
        fi
    done
    
    # Apply to worker nodes
    for node_data in $worker_nodes; do
        local node=$(echo "$node_data" | base64 --decode)
        local name=$(echo "$node" | jq -r '.key')
        local ip=$(echo "$node" | jq -r '.value.ip_address')
        local config="$TALOS_CONFIG_DIR/worker-${name}.yaml"
        
        log "Applying config to $name ($ip)..."
        if talosctl apply-config \
            --talosconfig "$TALOS_CONFIG_DIR/talosconfig" \
            --nodes "$ip" \
            --file "$config" \
            --insecure; then
            success "Config applied to $name"
        else
            warn "Failed to apply config to $name (may already be configured)"
        fi
    done
    
    success "All configurations applied"
    log "Nodes are installing Talos to disk (takes 2-5 minutes)..."
}

# =============================================================================
# BOOTSTRAP - Bootstrap Kubernetes Cluster
# =============================================================================
cmd_bootstrap() {
    log "Bootstrapping Kubernetes cluster..."
    check_prerequisites
    
    cd "$INFRA_DIR"
    
    # Get first control plane IP
    local first_cp=$(terraform output -json control_plane_ips 2>/dev/null | jq -r '.[0]')
    
    log "Waiting for first control plane to be ready ($first_cp)..."
    local max_wait=600
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        if talosctl --talosconfig "$TALOS_CONFIG_DIR/talosconfig" \
            --nodes "$first_cp" \
            version &>/dev/null; then
            success "Node is ready"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        [ $((elapsed % 60)) -eq 0 ] && log "Still waiting... ($elapsed seconds)"
    done
    
    if [ $elapsed -ge $max_wait ]; then
        error "Timeout waiting for node to be ready"
    fi
    
    log "Bootstrapping Kubernetes..."
    if talosctl --talosconfig "$TALOS_CONFIG_DIR/talosconfig" \
        --nodes "$first_cp" \
        bootstrap 2>&1 | grep -q "already"; then
        warn "Cluster already bootstrapped"
    else
        success "Bootstrap initiated"
    fi
    
    log "Waiting for Kubernetes API..."
    sleep 30
    
    log "Retrieving kubeconfig..."
    talosctl --talosconfig "$TALOS_CONFIG_DIR/talosconfig" \
        --nodes "$first_cp" \
        kubeconfig "$TALOS_CONFIG_DIR/kubeconfig" --force
    
    export KUBECONFIG="$TALOS_CONFIG_DIR/kubeconfig"
    
    log "Waiting for nodes to appear..."
    local expected_nodes=9  # 3 CP + 6 workers
    local max_wait=300
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$ready_nodes" -eq "$expected_nodes" ]; then
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    success "Kubernetes cluster bootstrapped"
    echo ""
    log "Cluster status:"
    kubectl get nodes
    echo ""
    warn "Nodes will be NotReady until Cilium is installed"
    log "Next: Run './bootstrap.sh' to install Cilium and ArgoCD"
}

# =============================================================================
# STATUS - Check Cluster Status
# =============================================================================
cmd_status() {
    log "Checking cluster status..."
    
    if [ ! -f "$TALOS_CONFIG_DIR/kubeconfig" ]; then
        warn "Cluster not bootstrapped yet"
        return
    fi
    
    export KUBECONFIG="$TALOS_CONFIG_DIR/kubeconfig"
    
    echo ""
    log "Nodes:"
    kubectl get nodes -o wide
    
    echo ""
    log "System pods:"
    kubectl get pods -n kube-system
    
    echo ""
    log "Talos version:"
    cd "$INFRA_DIR"
    local first_cp=$(terraform output -json control_plane_ips 2>/dev/null | jq -r '.[0]')
    talosctl --talosconfig "$TALOS_CONFIG_DIR/talosconfig" \
        --nodes "$first_cp" \
        version --short 2>/dev/null || warn "Cannot connect to nodes"
}

# =============================================================================
# MAIN
# =============================================================================
show_usage() {
    cat << EOF
Usage: $(basename "$0") [command]

Commands:
    apply       Apply Talos configurations to nodes (install Talos)
    bootstrap   Bootstrap Kubernetes cluster (no CNI)
    status      Check cluster status
    (no args)   Full deployment (apply + bootstrap)

Examples:
    $(basename "$0")              # Full deployment
    $(basename "$0") apply        # Just install Talos
    $(basename "$0") bootstrap    # Just bootstrap K8s
    $(basename "$0") status       # Check status

EOF
}

case "${1:-deploy}" in
    apply)
        cmd_apply
        ;;
    bootstrap)
        cmd_bootstrap
        ;;
    status)
        cmd_status
        ;;
    deploy)
        cmd_apply
        echo ""
        cmd_bootstrap
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
