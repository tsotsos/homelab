#!/bin/bash
# =============================================================================
# KUBERNETES BOOTSTRAP SCRIPT
# =============================================================================
# Comprehensive bootstrap for Talos Kubernetes cluster
# Installs core components and seals secrets automatically
#
# Prerequisites:
#   - Talos cluster deployed (run ./deploy.sh first)
#   - Unsealed secrets in secrets-un/ directory
#
# Usage:
#   ./bootstrap.sh                    - Run full bootstrap
#   ./bootstrap.sh --step <N>         - Resume from specific step
#   ./bootstrap.sh --seal-secrets     - Only seal secrets
#   ./bootstrap.sh --help             - Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$PROJECT_ROOT/infra"
CLUSTER_DIR="$PROJECT_ROOT/cluster"
SECRETS_UNSEALED_DIR="$PROJECT_ROOT/secrets-un"
TALOS_CONFIG_DIR="$INFRA_DIR/talos-config"
STATE_FILE="$SCRIPT_DIR/.bootstrap-state"

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
step() { echo -e "${CYAN}━━━ STEP $1 ━━━${NC}"; }

# Set kubeconfig
export KUBECONFIG="$TALOS_CONFIG_DIR/kubeconfig"

# =============================================================================
# STATE MANAGEMENT
# =============================================================================
save_state() {
    echo "$1" > "$STATE_FILE"
    log "Progress saved: Step $1 completed"
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "0"
    fi
}

clear_state() {
    rm -f "$STATE_FILE"
    success "Bootstrap state cleared"
}

# =============================================================================
# HELP
# =============================================================================
show_help() {
    cat << EOF
Kubernetes Bootstrap Script

Usage:
  ./bootstrap.sh                    Run full bootstrap (or resume)
  ./bootstrap.sh --step <N>         Resume from specific step
  ./bootstrap.sh --seal-secrets     Only seal secrets
  ./bootstrap.sh --reset            Clear state and start fresh
  ./bootstrap.sh --help             Show this help

Steps:
  0. Apply node labels
  1. Install Cilium CNI
  2. Install kube-vip and kube-vip-cloud-provider
  3. Install sealed-secrets and seal all secrets
  4. Install external-dns
  5. Install cert-manager
  6. Install longhorn
  7. Install ArgoCD

Options:
  --step <N>        Resume from step N (0-7)
  --seal-secrets    Only seal secrets (requires sealed-secrets controller)
  --reset           Clear bootstrap state
  --help            Show this help

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
    command -v kubeseal >/dev/null 2>&1 || error "kubeseal not installed"
    
    if [ ! -f "$KUBECONFIG" ]; then
        error "Kubeconfig not found at $KUBECONFIG. Run ./deploy.sh first"
    fi
    
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to Kubernetes cluster. Ensure cluster is running"
    fi
    
    success "Prerequisites OK"
}

# =============================================================================
# STEP 0: APPLY NODE LABELS
# =============================================================================
step_0_apply_node_labels() {
    step "0: APPLYING NODE LABELS"
    
    local config_file="$INFRA_DIR/cluster-config.yaml"
    
    if [ ! -f "$config_file" ]; then
        error "cluster-config.yaml not found at $config_file"
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
    kubectl get nodes -o wide
    echo ""
    
    success "Node labels applied"
    save_state 0
}

# =============================================================================
# STEP 1: INSTALL CILIUM CNI
# =============================================================================
step_1_install_cilium() {
    step "1: INSTALLING CILIUM CNI"
    
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
    kubectl wait --for=condition=Ready pods -l k8s-app=cilium -n kube-system --timeout=300s
    
    log "Waiting for nodes to become Ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    success "Cilium installed and operational"
    echo ""
    kubectl get nodes -o wide
    echo ""
    
    save_state 1
}

# =============================================================================
# STEP 2: INSTALL KUBE-VIP AND KUBE-VIP-CLOUD-PROVIDER
# =============================================================================
step_2_install_kube_vip() {
    step "2: INSTALLING KUBE-VIP AND KUBE-VIP-CLOUD-PROVIDER"
    
    # Install kube-vip
    log "Installing kube-vip..."
    if kubectl get daemonset -n kube-system kube-vip &>/dev/null; then
        warn "kube-vip already installed"
    else
        kustomize build --enable-helm "$CLUSTER_DIR/network/kube-vip" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/network/kube-vip/charts" 2>/dev/null || true
        
        log "Waiting for kube-vip to be ready..."
        kubectl rollout status daemonset kube-vip -n kube-system --timeout=120s
        success "kube-vip installed"
    fi
    
    # Install kube-vip-cloud-provider
    log "Installing kube-vip-cloud-provider..."
    if kubectl get deployment -n kube-system kube-vip-cloud-provider &>/dev/null; then
        warn "kube-vip-cloud-provider already installed"
    else
        kustomize build --enable-helm "$CLUSTER_DIR/network/kube-vip-cloud-provider" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/network/kube-vip-cloud-provider/charts" 2>/dev/null || true
        
        log "Waiting for kube-vip-cloud-provider to be ready..."
        kubectl rollout status deployment kube-vip-cloud-provider -n kube-system --timeout=120s
        success "kube-vip-cloud-provider installed"
    fi
    
    save_state 2
}

# =============================================================================
# STEP 3: INSTALL SEALED-SECRETS AND SEAL ALL SECRETS
# =============================================================================
step_3_install_sealed_secrets() {
    step "3: INSTALLING SEALED-SECRETS AND SEALING SECRETS"
    
    # Install sealed-secrets controller
    log "Installing sealed-secrets controller..."
    if kubectl get deployment -n kube-system sealed-secrets &>/dev/null; then
        warn "sealed-secrets already installed"
    else
        kustomize build --enable-helm "$CLUSTER_DIR/security/sealed-secrets" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/security/sealed-secrets/charts" 2>/dev/null || true
        
        log "Waiting for sealed-secrets to be ready..."
        kubectl rollout status deployment sealed-secrets -n kube-system --timeout=120s
    fi
    
    # Wait a bit for the controller to fully initialize
    sleep 5
    
    success "sealed-secrets controller installed"
    
    # Seal secrets
    seal_all_secrets
    
    save_state 3
}

# =============================================================================
# SEAL ALL SECRETS FUNCTION
# =============================================================================
seal_all_secrets() {
    log "Sealing all secrets in $SECRETS_UNSEALED_DIR..."
    
    if [ ! -d "$SECRETS_UNSEALED_DIR" ]; then
        error "Unsealed secrets directory not found: $SECRETS_UNSEALED_DIR"
    fi
    
    # Find all yaml files in secrets-un directory (excluding temp files)
    local secret_files=$(find "$SECRETS_UNSEALED_DIR" -maxdepth 1 -name "*.yaml" -type f ! -name "*-tmp-*")
    
    if [ -z "$secret_files" ]; then
        warn "No unsealed secrets found in $SECRETS_UNSEALED_DIR"
        return 0
    fi
    
    local sealed_count=0
    
    for secret_file in $secret_files; do
        local filename=$(basename "$secret_file")
        local secret_name="${filename%.yaml}"
        
        info "Processing: $filename"
        
        # Extract namespace from the secret file
        local namespace=$(yq eval '.metadata.namespace' "$secret_file")
        
        if [ "$namespace" = "null" ] || [ -z "$namespace" ]; then
            warn "Skipping $filename - no namespace defined"
            continue
        fi
        
        # Try to find matching directory in cluster/
        local target_dir=""
        
        # Search for directory matching the namespace or secret name
        target_dir=$(find "$CLUSTER_DIR" -type d -name "$namespace" -o -name "$secret_name" | head -n 1)
        
        # If not found, try common patterns
        if [ -z "$target_dir" ]; then
            case "$namespace" in
                "monitoring")
                    target_dir="$CLUSTER_DIR/observability/kube-prometheus-stack"
                    ;;
                "cert-manager")
                    target_dir="$CLUSTER_DIR/security/cert-manager"
                    ;;
                "external-dns")
                    target_dir="$CLUSTER_DIR/network/external-dns"
                    ;;
                "postgresql")
                    target_dir="$CLUSTER_DIR/database/postgresql"
                    ;;
                "authentik")
                    target_dir="$CLUSTER_DIR/security/authentik"
                    ;;
                "kube-system")
                    target_dir="$CLUSTER_DIR/security/sealed-secrets"
                    ;;
            esac
        fi
        
        if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
            warn "Cannot find target directory for namespace: $namespace (searched for: $secret_name)"
            continue
        fi
        
        local output_file="$target_dir/sealed-secret.yaml"
        
        log "Sealing $filename -> $output_file"
        
        # Seal the secret using kubeseal (accessing the cluster directly)
        if kubeseal --controller-name sealed-secrets --controller-namespace kube-system --format yaml < "$secret_file" > "$output_file" 2>/dev/null; then
            # Remove creationTimestamp from metadata if present
            yq eval 'del(.metadata.creationTimestamp)' -i "$output_file"
            # Remove creationTimestamp from template.metadata if present
            yq eval 'del(.spec.template.metadata.creationTimestamp)' -i "$output_file"
            
            success "Sealed: $filename -> $(basename "$target_dir")/sealed-secret.yaml"
            ((sealed_count++))
        else
            error "Failed to seal $filename"
        fi
    done
    
    echo ""
    success "Sealed $sealed_count secret(s)"
}

# =============================================================================
# STEP 4: INSTALL EXTERNAL-DNS
# =============================================================================
step_4_install_external_dns() {
    step "4: INSTALLING EXTERNAL-DNS"
    
    if kubectl get deployment -n external-dns external-dns-unifi &>/dev/null; then
        warn "external-dns already installed"
    else
        log "Installing external-dns..."
        kustomize build --enable-helm "$CLUSTER_DIR/network/external-dns" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/network/external-dns/charts" 2>/dev/null || true
        
        log "Waiting for external-dns to be ready..."
        kubectl rollout status deployment external-dns-unifi -n external-dns --timeout=120s
        success "external-dns installed"
    fi
    
    save_state 4
}

# =============================================================================
# STEP 5: INSTALL CERT-MANAGER
# =============================================================================
step_5_install_cert_manager() {
    step "5: INSTALLING CERT-MANAGER"
    
    if kubectl get deployment -n cert-manager cert-manager &>/dev/null; then
        warn "cert-manager already installed"
    else
        log "Installing cert-manager..."
        kustomize build --enable-helm "$CLUSTER_DIR/security/cert-manager" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/security/cert-manager/charts" 2>/dev/null || true
        
        log "Waiting for cert-manager to be ready..."
        kubectl rollout status deployment cert-manager -n cert-manager --timeout=180s
        kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=180s
        kubectl rollout status deployment cert-manager-cainjector -n cert-manager --timeout=180s
        success "cert-manager installed"
    fi
    
    save_state 5
}

# =============================================================================
# STEP 6: INSTALL LONGHORN
# =============================================================================
step_6_install_longhorn() {
    step "6: INSTALLING LONGHORN"
    
    if kubectl get namespace longhorn-system &>/dev/null; then
        warn "longhorn already installed"
    else
        log "Installing longhorn..."
        kustomize build --enable-helm "$CLUSTER_DIR/storage/longhorn" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/storage/longhorn/charts" 2>/dev/null || true
        
        log "Waiting for longhorn to be ready (this may take a few minutes)..."
        kubectl wait --for=condition=Ready pods -l app=longhorn-manager -n longhorn-system --timeout=300s
        success "longhorn installed"
    fi
    
    save_state 6
}

# =============================================================================
# STEP 7: INSTALL ARGOCD
# =============================================================================
step_7_install_argocd() {
    step "7: INSTALLING ARGOCD"
    
    if kubectl get namespace argocd &>/dev/null; then
        warn "ArgoCD already installed"
    else
        log "Installing ArgoCD..."
        kustomize build --enable-helm "$CLUSTER_DIR/argocd" | kubectl apply -f -
        rm -rf "$CLUSTER_DIR/argocd/charts" 2>/dev/null || true
        
        log "Waiting for ArgoCD to be ready..."
        kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
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
    
    save_state 7
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    local start_step=0
    local only_seal=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --step)
                start_step="$2"
                shift 2
                ;;
            --seal-secrets)
                only_seal=true
                shift
                ;;
            --reset)
                clear_state
                exit 0
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
    echo "║         KUBERNETES CLUSTER BOOTSTRAP                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    
    # If only sealing secrets
    if [ "$only_seal" = true ]; then
        if ! kubectl get deployment -n kube-system sealed-secrets &>/dev/null; then
            error "sealed-secrets controller not installed. Run full bootstrap first."
        fi
        seal_all_secrets
        success "Secret sealing completed"
        exit 0
    fi
    
    # Load saved state if resuming
    local saved_step=$(load_state)
    if [ "$start_step" -eq 0 ] && [ "$saved_step" -gt 0 ]; then
        info "Found previous bootstrap state at step $saved_step"
        read -p "Resume from step $((saved_step + 1))? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            start_step=$((saved_step + 1))
        else
            clear_state
        fi
    fi
    
    # Execute steps
    if [ "$start_step" -le 0 ]; then step_0_apply_node_labels; fi
    if [ "$start_step" -le 1 ]; then step_1_install_cilium; fi
    if [ "$start_step" -le 2 ]; then step_2_install_kube_vip; fi
    if [ "$start_step" -le 3 ]; then step_3_install_sealed_secrets; fi
    if [ "$start_step" -le 4 ]; then step_4_install_external_dns; fi
    if [ "$start_step" -le 5 ]; then step_5_install_cert_manager; fi
    if [ "$start_step" -le 6 ]; then step_6_install_longhorn; fi
    if [ "$start_step" -le 7 ]; then step_7_install_argocd; fi
    
    # Clear state on successful completion
    clear_state
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         BOOTSTRAP COMPLETED SUCCESSFULLY! 🎉               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    success "All components installed and configured"
    info "Next steps:"
    echo "  1. Access ArgoCD and deploy applications"
    echo "  2. Verify all pods are running: kubectl get pods -A"
    echo "  3. Check sealed secrets: kubectl get sealedsecrets -A"
    echo ""
}

# Run main function
main "$@"
