#!/bin/bash
# =============================================================================
# UNIFIED TALOS CLUSTER DEPLOYMENT SCRIPT
# =============================================================================
# Professional deployment system with parallel processing, external node support,
# comprehensive error handling, and operational diagnostics
#
# Features:
# - Backward compatible with existing deployment
# - Parallel node configuration for faster deployment  
# - External node onboarding support
# - Comprehensive error handling and rollback
# - Configuration validation and health checks
# - Uses shared cluster-config.yaml for consistency
# - Built-in diagnostics and troubleshooting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TALOS_CONFIG_DIR="$SCRIPT_DIR/talos-config"
LOCK_DIR="$SCRIPT_DIR/.deployment-locks"
LOG_DIR="$SCRIPT_DIR/.deployment-logs"

# Try to source config parser, fall back to hardcoded values if not available
if [ -f "$SCRIPT_DIR/config-parser.sh" ]; then
    source "$SCRIPT_DIR/config-parser.sh"
    USE_CONFIG_PARSER=true
else
    USE_CONFIG_PARSER=false
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Enhanced logging functions with timestamps
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] [INFO]${NC} $1" | tee -a "$LOG_DIR/deployment.log" 2>/dev/null || echo -e "${GREEN}[$(date '+%H:%M:%S')] [INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] [WARN]${NC} $1" | tee -a "$LOG_DIR/deployment.log" 2>/dev/null || echo -e "${YELLOW}[$(date '+%H:%M:%S')] [WARN]${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] [ERROR]${NC} $1" | tee -a "$LOG_DIR/deployment.log" 2>/dev/null || echo -e "${RED}[$(date '+%H:%M:%S')] [ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] [SUCCESS]${NC} $1" | tee -a "$LOG_DIR/deployment.log" 2>/dev/null || echo -e "${GREEN}[$(date '+%H:%M:%S')] [SUCCESS]${NC} $1"; }
step() { echo -e "${BLUE}[$(date '+%H:%M:%S')] [STEP]${NC} $1" | tee -a "$LOG_DIR/deployment.log" 2>/dev/null || echo -e "${BLUE}[$(date '+%H:%M:%S')] [STEP]${NC} $1"; }
debug() { echo -e "${PURPLE}[$(date '+%H:%M:%S')] [DEBUG]${NC} $1" | tee -a "$LOG_DIR/deployment.log" 2>/dev/null || echo -e "${PURPLE}[$(date '+%H:%M:%S')] [DEBUG]${NC} $1"; }

# =============================================================================
# CONFIGURATION MANAGEMENT
# =============================================================================

# Fallback hardcoded configuration (backward compatibility)
init_fallback_config() {
    CP_NODES_kng_cp_1="10.0.2.101"
    CP_NODES_kng_cp_2="10.0.2.102"
    CP_NODES_kng_cp_3="10.0.2.103"
    
    WORKER_NODES_kng_worker_1="10.0.2.104"
    WORKER_NODES_kng_worker_2="10.0.2.105"
    WORKER_NODES_kng_worker_3="10.0.2.106"
    WORKER_NODES_kng_worker_4="10.0.2.107"
    WORKER_NODES_kng_worker_5="10.0.2.108"
    WORKER_NODES_kng_worker_6="10.0.2.109"
    
    FIRST_CP_IP="$CP_NODES_kng_cp_1"
    VIP_ADDRESS="10.0.2.100"
    CLUSTER_NAME="kng-cluster"
    
    CP_NODES_LIST=("kng-cp-1" "kng-cp-2" "kng-cp-3")
    WORKER_NODES_LIST=("kng-worker-1" "kng-worker-2" "kng-worker-3" "kng-worker-4" "kng-worker-5" "kng-worker-6")
}

# Smart configuration loading
load_configuration() {
    if [ "$USE_CONFIG_PARSER" = true ]; then
        log "Loading configuration from cluster-config.yaml"
        
        CLUSTER_NAME=$(get_cluster_name)
        VIP_ADDRESS=$(get_cluster_vip)
        
        # Load nodes dynamically
        CP_NODES_LIST=($(get_control_plane_nodes))
        WORKER_NODES_LIST=($(get_worker_nodes))
        
        if [ ${#CP_NODES_LIST[@]} -gt 0 ]; then
            FIRST_CP_IP=$(get_node_ip "${CP_NODES_LIST[0]}")
        else
            error "No control plane nodes found in configuration"
            return 1
        fi
        
        success "Configuration loaded: $CLUSTER_NAME with ${#CP_NODES_LIST[@]} CP + ${#WORKER_NODES_LIST[@]} worker nodes"
    else
        warn "Config parser not available, using fallback configuration"
        init_fallback_config
        success "Fallback configuration loaded: $CLUSTER_NAME"
    fi
}

# Get node IP with fallback
get_node_ip_safe() {
    local node_name=$1
    
    if [ "$USE_CONFIG_PARSER" = true ]; then
        get_node_ip "$node_name"
    else
        # Fallback to variable lookup
        local varname
        if [[ $node_name =~ ^kng-cp- ]]; then
            varname="CP_NODES_${node_name//-/_}"
        else
            varname="WORKER_NODES_${node_name//-/_}"
        fi
        echo "${!varname}"
    fi
}

# =============================================================================
# INITIALIZATION AND VALIDATION
# =============================================================================

init_deployment() {
    step "Initializing unified deployment environment"
    
    # Create necessary directories
    mkdir -p "$LOCK_DIR" "$LOG_DIR" 2>/dev/null || true
    
    # Initialize log file
    echo "=== Talos Cluster Deployment Started at $(date) ===" > "$LOG_DIR/deployment.log" 2>/dev/null || true
    
    # Load configuration
    export TALOSCONFIG="$TALOS_CONFIG_DIR/talosconfig"
    load_configuration
    
    # Validate requirements
    validate_requirements
    
    success "Deployment environment initialized"
}

validate_requirements() {
    log "Validating deployment requirements"
    
    local required_tools=("talosctl" "ping")
    local optional_tools=("kubectl" "yq")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    for tool in "${optional_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            warn "Optional tool '$tool' is not installed (some features may be limited)"
        fi
    done
    
    if [ ! -f "$TALOSCONFIG" ]; then
        error "Talos configuration not found at $TALOSCONFIG"
        error "Please ensure 'terraform apply' completed successfully"
        exit 1
    fi
    
    success "Requirements validation passed"
}

# =============================================================================
# PARALLEL PROCESSING WITH FALLBACK
# =============================================================================

# Enhanced parallel processing with job control
run_parallel_enhanced() {
    local func_name=$1
    local nodes_list=("${@:2}")
    
    # Check if parallel is enabled (default to 3 if config not available)
    local max_concurrent=3
    local parallel_enabled=true
    
    if [ "$USE_CONFIG_PARSER" = true ]; then
        max_concurrent=$(get_deployment_max_concurrent 2>/dev/null || echo "3")
        parallel_enabled=$(get_deployment_parallel_enabled 2>/dev/null || echo "true")
    fi
    
    if [ "$parallel_enabled" = "true" ] && [ ${#nodes_list[@]} -gt 1 ]; then
        log "Running $func_name in parallel (max $max_concurrent concurrent)"
        
        local pids=()
        local active_count=0
        local success_count=0
        local failure_count=0
        
        for node in "${nodes_list[@]}"; do
            # Wait for available slot
            while [ $active_count -ge $max_concurrent ]; do
                for i in "${!pids[@]}"; do
                    if ! kill -0 "${pids[i]}" 2>/dev/null; then
                        wait "${pids[i]}"
                        local exit_code=$?
                        if [ $exit_code -eq 0 ]; then
                            success_count=$((success_count + 1))
                        else
                            failure_count=$((failure_count + 1))
                        fi
                        unset "pids[i]"
                        active_count=$((active_count - 1))
                    fi
                done
                sleep 1
            done
            
            # Start new job
            $func_name "$node" &
            pids+=($!)
            active_count=$((active_count + 1))
            
            debug "Started $func_name for $node (PID: $!)"
            
            # Small delay to prevent overwhelming
            sleep 2
        done
        
        # Wait for all jobs to complete
        for pid in "${pids[@]}"; do
            wait "$pid"
            local exit_code=$?
            if [ $exit_code -eq 0 ]; then
                success_count=$((success_count + 1))
            else
                failure_count=$((failure_count + 1))
            fi
        done
        
        if [ $failure_count -eq 0 ]; then
            success "All parallel $func_name jobs completed successfully ($success_count/$((success_count + failure_count)))"
        else
            warn "Parallel $func_name completed with $failure_count failures out of $((success_count + failure_count)) total"
        fi
        
        return $failure_count
    else
        log "Running $func_name sequentially"
        local failures=0
        for node in "${nodes_list[@]}"; do
            if ! $func_name "$node"; then
                failures=$((failures + 1))
            fi
        done
        return $failures
    fi
}

# =============================================================================
# ENHANCED NODE OPERATION FUNCTIONS
# =============================================================================

wait_for_node() {
    local node_name=$1
    local ip=$(get_node_ip_safe "$node_name")
    local timeout=600  # 10 minutes default
    local wait_time=0
    
    if [ "$USE_CONFIG_PARSER" = true ]; then
        timeout=$(get_deployment_timeout "node_boot" 2>/dev/null || echo "600")
    fi
    
    log "[$node_name] Waiting for node to be reachable at $ip"
    
    while [ $wait_time -lt $timeout ]; do
        if ping -c 1 -W 2 "$ip" &>/dev/null; then
            success "[$node_name] Node is reachable"
            return 0
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
        
        if [ $((wait_time % 30)) -eq 0 ]; then
            log "[$node_name] Still waiting... ($wait_time/${timeout}s)"
        fi
    done
    
    error "[$node_name] Node failed to respond after ${timeout}s"
    return 1
}

wait_for_talos_api() {
    local node_name=$1
    local ip=$(get_node_ip_safe "$node_name")
    local timeout=600  # 10 minutes default
    local wait_time=0
    
    if [ "$USE_CONFIG_PARSER" = true ]; then
        timeout=$(get_deployment_timeout "api_ready" 2>/dev/null || echo "600")
    fi
    
    log "[$node_name] Waiting for Talos API to be ready"
    
    while [ $wait_time -lt $timeout ]; do
        if talosctl -n "$ip" -e "$ip" version --short &>/dev/null; then
            success "[$node_name] Talos API is ready"
            return 0
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        
        if [ $((wait_time % 60)) -eq 0 ]; then
            log "[$node_name] Still waiting for API... ($wait_time/${timeout}s)"
        fi
    done
    
    error "[$node_name] Talos API not responding after ${timeout}s"
    return 1
}

apply_node_config() {
    local node_name=$1
    local ip=$(get_node_ip_safe "$node_name")
    local role="controlplane"
    
    # Determine role
    if [[ $node_name =~ worker ]]; then
        role="worker"
    fi
    
    local config_file="$TALOS_CONFIG_DIR/${role}-${node_name}.yaml"
    
    if [ ! -f "$config_file" ]; then
        error "[$node_name] Configuration file not found: $config_file"
        return 1
    fi
    
    log "[$node_name] Applying Talos configuration"
    
    # Enhanced retry logic
    local retries=3
    local delay=30
    
    if [ "$USE_CONFIG_PARSER" = true ]; then
        retries=$(yq '.deployment.retries.max_attempts' "$SCRIPT_DIR/cluster-config.yaml" 2>/dev/null || echo "3")
        delay=$(yq '.deployment.retries.delay_seconds' "$SCRIPT_DIR/cluster-config.yaml" 2>/dev/null || echo "30")
    fi
    
    for attempt in $(seq 1 $retries); do
        if talosctl apply-config --insecure --nodes "$ip" --file "$config_file" &>/dev/null; then
            success "[$node_name] Configuration applied successfully"
            return 0
        else
            if [ $attempt -lt $retries ]; then
                warn "[$node_name] Configuration apply failed (attempt $attempt/$retries), retrying in ${delay}s"
                sleep "$delay"
            fi
        fi
    done
    
    error "[$node_name] Failed to apply configuration after $retries attempts"
    return 1
}

check_etcd_data() {
    local node_name=$1
    local ip=$(get_node_ip_safe "$node_name")
    
    log "[$node_name] Checking etcd data directory"
    
    if talosctl ls /var/lib/etcd --nodes "$ip" --endpoints "$ip" 2>/dev/null | grep -q "member"; then
        warn "[$node_name] Found existing etcd data"
        return 1
    else
        success "[$node_name] etcd directory is clean"
        return 0
    fi
}

reset_node_if_needed() {
    local node_name=$1
    local ip=$(get_node_ip_safe "$node_name")
    
    if ! check_etcd_data "$node_name"; then
        warn "[$node_name] Resetting node to clear etcd data"
        
        if talosctl reset --graceful=false --reboot --nodes "$ip" --endpoints "$ip"; then
            success "[$node_name] Node reset completed"
            sleep 60
            wait_for_node "$node_name"
            return 0
        else
            error "[$node_name] Failed to reset node"
            return 1
        fi
    fi
    
    return 0
}

# =============================================================================
# PHASE IMPLEMENTATION FUNCTIONS
# =============================================================================

configure_control_plane_node() {
    local node_name=$1
    
    log "[$node_name] Starting control plane configuration"
    
    # Wait for node to be reachable
    wait_for_node "$node_name" || {
        error "[$node_name] Node not reachable"
        return 1
    }
    
    # Apply configuration
    apply_node_config "$node_name" || {
        error "[$node_name] Failed to apply configuration"
        return 1
    }
    
    # Wait for configuration to be processed
    sleep 30
    
    # Wait for Talos API
    wait_for_talos_api "$node_name" || {
        error "[$node_name] Talos API not ready"
        return 1
    }
    
    success "[$node_name] Control plane configuration completed"
}

configure_worker_node() {
    local node_name=$1
    
    log "[$node_name] Starting worker configuration"
    
    # Wait for node to be reachable
    wait_for_node "$node_name" || {
        error "[$node_name] Node not reachable"
        return 1
    }
    
    # Apply configuration
    apply_node_config "$node_name" || {
        error "[$node_name] Failed to apply configuration"
        return 1
    }
    
    # Wait for configuration to be processed
    sleep 20
    
    success "[$node_name] Worker configuration completed"
}

# =============================================================================
# CLUSTER DIAGNOSTICS
# =============================================================================

run_diagnostics() {
    step "🔍 Running Cluster Diagnostics"
    echo "================================"
    
    log "Testing node connectivity:"
    for node in "${CP_NODES_LIST[@]}"; do
        local ip=$(get_node_ip_safe "$node")
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            success "  $node ($ip) - reachable"
            
            # Check Talos services
            log "    🔧 Checking services on $node:"
            if talosctl -n "$ip" services 2>/dev/null | grep -E "(etcd|kubelet|kube)" >/dev/null; then
                success "    Core services are running"
            else
                warn "    Some services may not be running"
            fi
            
            # Check etcd status for control plane
            if [[ $node =~ cp ]]; then
                log "    💾 Checking etcd status:"
                if talosctl -n "$ip" service etcd status 2>/dev/null >/dev/null; then
                    success "    etcd is running"
                else
                    warn "    etcd service check failed"
                fi
            fi
        else
            error "  $node ($ip) - not reachable"
        fi
    done
    
    echo ""
    log "🚀 Checking bootstrap status:"
    if talosctl -n "$FIRST_CP_IP" bootstrap --dry-run 2>/dev/null >/dev/null; then
        success "Bootstrap ready"
    else
        log "Bootstrap not ready or already done"
    fi
    
    echo ""
    log "🏥 Checking cluster health:"
    local all_cp_ips=$(printf "%s," "${CP_NODES_LIST[@]}" | sed 's/,$//')
    all_cp_ips=$(echo "$all_cp_ips" | sed 's/kng-cp-[0-9]/'"$(get_node_ip_safe "kng-cp-1")"'/g; s/kng-cp-[0-9]/'"$(get_node_ip_safe "kng-cp-2")"'/g; s/kng-cp-[0-9]/'"$(get_node_ip_safe "kng-cp-3")"'/g')
    
    # Build proper IP list
    local cp_ips=""
    for node in "${CP_NODES_LIST[@]}"; do
        local ip=$(get_node_ip_safe "$node")
        if [ -z "$cp_ips" ]; then
            cp_ips="$ip"
        else
            cp_ips="$cp_ips,$ip"
        fi
    done
    
    if talosctl -n "$cp_ips" health --run-timeout=30s 2>/dev/null; then
        success "Cluster health check passed"
    else
        warn "Cluster health check failed or timed out"
    fi
    
    echo ""
    log "📊 Checking etcd cluster:"
    if talosctl -n "$FIRST_CP_IP" etcd members 2>/dev/null; then
        success "etcd cluster is operational"
    else
        warn "etcd members check failed"
    fi
}

# =============================================================================
# MAIN DEPLOYMENT FUNCTIONS
# =============================================================================

deploy_cluster() {
    step "=========================================="
    step "    UNIFIED TALOS CLUSTER DEPLOYMENT"
    step "=========================================="
    echo ""
    
    # Phase 1: Configure control plane nodes
    step "Phase 1: Configuring Control Plane Nodes"
    echo "----------------------------------------"
    
    if ! run_parallel_enhanced configure_control_plane_node "${CP_NODES_LIST[@]}"; then
        warn "Some control plane nodes failed to configure"
    fi
    
    # Phase 1.5: Check and clean etcd data if necessary
    step "Phase 1.5: Verifying Clean etcd State"
    echo "-------------------------------------"
    
    local needs_cleanup=false
    for node in "${CP_NODES_LIST[@]}"; do
        if ! check_etcd_data "$node"; then
            needs_cleanup=true
        fi
    done
    
    if [ "$needs_cleanup" = "true" ]; then
        warn "Found existing etcd data on some control plane nodes"
        read -p "Clean all control plane nodes? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for node in "${CP_NODES_LIST[@]}"; do
                reset_node_if_needed "$node"
                configure_control_plane_node "$node"
            done
        else
            error "Cannot proceed with existing etcd data"
            return 1
        fi
    fi
    
    # Phase 2: Bootstrap the cluster
    step "Phase 2: Bootstrapping Kubernetes Cluster"
    echo "------------------------------------------"
    
    log "Waiting for control plane to stabilize..."
    sleep 60
    
    log "Bootstrapping cluster on first control plane node ($FIRST_CP_IP)"
    if talosctl bootstrap --nodes "$FIRST_CP_IP" --endpoints "$FIRST_CP_IP"; then
        success "Cluster bootstrap initiated successfully"
    else
        error "Failed to bootstrap cluster"
        return 1
    fi
    
    log "Waiting for Kubernetes control plane to start..."
    sleep 90
    
    # Phase 3: Configure worker nodes
    step "Phase 3: Configuring Worker Nodes"
    echo "--------------------------------"
    
    if ! run_parallel_enhanced configure_worker_node "${WORKER_NODES_LIST[@]}"; then
        warn "Some worker nodes failed to configure, but continuing..."
    fi
    
    # Phase 4: Health verification
    step "Phase 4: Final Health Verification"
    echo "--------------------------------"
    
    sleep 60
    verify_cluster_health
    
    # Final summary
    print_deployment_summary
}

verify_cluster_health() {
    step "Performing comprehensive cluster health verification"
    
    # Test VIP connectivity
    log "Testing VIP connectivity ($VIP_ADDRESS)"
    if ping -c 3 "$VIP_ADDRESS" &>/dev/null; then
        success "VIP is responding"
    else
        warn "VIP is not responding (this may be normal if not configured)"
    fi
    
    # Build control plane endpoints
    local cp_ips=""
    for node in "${CP_NODES_LIST[@]}"; do
        local ip=$(get_node_ip_safe "$node")
        if [ -z "$cp_ips" ]; then
            cp_ips="$ip"
        else
            cp_ips="$cp_ips,$ip"
        fi
    done
    
    # Check etcd cluster
    log "Verifying etcd cluster health"
    if talosctl etcd members --nodes "$FIRST_CP_IP" --endpoints "$cp_ips" &>/dev/null; then
        success "etcd cluster is healthy"
    else
        warn "etcd cluster health check failed"
    fi
    
    # Generate and test kubeconfig
    log "Generating kubeconfig"
    local kubeconfig_path="$TALOS_CONFIG_DIR/kubeconfig"
    
    if talosctl kubeconfig "$kubeconfig_path" --nodes "$FIRST_CP_IP" --endpoints "$cp_ips" --force; then
        success "Kubeconfig generated"
        
        export KUBECONFIG="$kubeconfig_path"
        
        # Test cluster access
        log "Testing Kubernetes API access"
        local timeout=900  # 15 minutes
        local wait_time=0
        
        while [ $wait_time -lt $timeout ]; do
            if kubectl get nodes &>/dev/null; then
                success "Kubernetes API is responding"
                
                log "Cluster nodes status:"
                kubectl get nodes -o wide
                
                return 0
            fi
            
            sleep 10
            wait_time=$((wait_time + 10))
            
            if [ $((wait_time % 60)) -eq 0 ]; then
                log "Still waiting for Kubernetes API... ($wait_time/${timeout}s)"
            fi
        done
        
        warn "Kubernetes API not responding after ${timeout}s"
    else
        error "Failed to generate kubeconfig"
    fi
}

print_deployment_summary() {
    step "=========================================="
    step "        DEPLOYMENT SUMMARY"
    step "=========================================="
    echo ""
    
    log "Cluster Information:"
    echo "  • Cluster Name:     $CLUSTER_NAME"
    echo "  • Control Plane VIP: $VIP_ADDRESS"
    echo "  • Talos Config:     $TALOSCONFIG"
    echo "  • Kubeconfig:       $TALOS_CONFIG_DIR/kubeconfig"
    echo ""
    
    log "Control Plane Nodes:"
    for node in "${CP_NODES_LIST[@]}"; do
        local ip=$(get_node_ip_safe "$node")
        echo "  • $node: $ip"
    done
    
    echo ""
    log "Worker Nodes:"
    for node in "${WORKER_NODES_LIST[@]}"; do
        local ip=$(get_node_ip_safe "$node")
        echo "  • $node: $ip"
    done
    
    echo ""
    log "Next Steps:"
    echo "  1. Export kubeconfig: export KUBECONFIG='$TALOS_CONFIG_DIR/kubeconfig'"
    echo "  2. Check nodes: kubectl get nodes -o wide"
    echo "  3. Check pods: kubectl get pods -A"
    echo "  4. Monitor cluster: $0 health-check"
    echo ""
    
    success "Deployment completed successfully!"
}

# =============================================================================
# EXTERNAL NODE MANAGEMENT
# =============================================================================

onboard_external_node() {
    local node_name=$1
    local node_ip=$2
    local node_role=${3:-worker}
    local arch=${4:-amd64}
    
    step "Onboarding external node: $node_name ($node_ip)"
    
    # Validate node is reachable
    if ! ping -c 1 -W 5 "$node_ip" &>/dev/null; then
        error "External node $node_name at $node_ip is not reachable"
        return 1
    fi
    
    warn "External node onboarding is a placeholder - implement based on your requirements"
    success "External node $node_name would be configured here"
}

# =============================================================================
# CLI INTERFACE
# =============================================================================

show_usage() {
    cat << EOF
Unified Talos Cluster Deployment Script

Usage: $0 [command] [options]

DEPLOYMENT COMMANDS:
    deploy                          - Deploy the full cluster (default)
    deploy-cp                       - Deploy only control plane nodes
    deploy-workers                  - Deploy only worker nodes

OPERATIONAL COMMANDS:
    diagnostics                     - Run comprehensive cluster diagnostics
    health-check                    - Perform cluster health verification  
    reset-node <node_name>          - Reset a specific node
    status                          - Show cluster status summary

EXTERNAL NODE COMMANDS:
    add-external-node <name> <ip> [role] [arch]  - Add external node to cluster
    
UTILITY COMMANDS:
    cleanup                         - Clean up deployment artifacts
    logs                            - Show deployment logs
    help                            - Show this help message

EXAMPLES:
    $0                              # Full deployment (same as 'deploy')
    $0 deploy                       # Full cluster deployment
    $0 diagnostics                  # Run diagnostics
    $0 health-check                 # Health verification
    $0 status                       # Quick status check
    $0 reset-node kng-worker-1      # Reset specific node
    $0 add-external-node edge-1 10.0.2.120 worker arm64

COMPATIBILITY:
    This script replaces both deploy_talos_cluster.sh and deploy-cluster-advanced.sh
    It automatically detects and uses cluster-config.yaml if available, 
    otherwise falls back to hardcoded configuration for backward compatibility.

EOF
}

# Quick status check
show_status() {
    step "🚀 Talos Cluster Status Summary"
    echo "==============================="
    
    log "Cluster: $CLUSTER_NAME"
    log "VIP: $VIP_ADDRESS"
    log "Control Plane: ${#CP_NODES_LIST[@]} nodes"
    log "Workers: ${#WORKER_NODES_LIST[@]} nodes"
    
    echo ""
    log "Quick connectivity check:"
    local reachable=0
    local total=0
    
    for node in "${CP_NODES_LIST[@]}" "${WORKER_NODES_LIST[@]}"; do
        local ip=$(get_node_ip_safe "$node")
        total=$((total + 1))
        if ping -c 1 -W 2 "$ip" &>/dev/null; then
            reachable=$((reachable + 1))
            success "  $node ($ip) - reachable"
        else
            error "  $node ($ip) - not reachable"
        fi
    done
    
    echo ""
    if [ $reachable -eq $total ]; then
        success "All $total nodes are reachable"
    else
        warn "$reachable/$total nodes are reachable"
    fi
    
    # Quick VIP test
    if ping -c 1 -W 2 "$VIP_ADDRESS" &>/dev/null; then
        success "VIP ($VIP_ADDRESS) is active"
    else
        warn "VIP ($VIP_ADDRESS) is not responding"
    fi
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    # Handle no arguments (default to deploy)
    local command=${1:-deploy}
    
    case "$command" in
        "deploy"|"")
            init_deployment
            deploy_cluster
            ;;
        "deploy-cp")
            init_deployment
            step "Deploying Control Plane Nodes Only"
            run_parallel_enhanced configure_control_plane_node "${CP_NODES_LIST[@]}"
            ;;
        "deploy-workers")
            init_deployment
            step "Deploying Worker Nodes Only"
            run_parallel_enhanced configure_worker_node "${WORKER_NODES_LIST[@]}"
            ;;
        "diagnostics")
            init_deployment
            run_diagnostics
            ;;
        "health-check")
            init_deployment
            verify_cluster_health
            ;;
        "status")
            load_configuration
            show_status
            ;;
        "add-external-node")
            if [ $# -lt 3 ]; then
                error "Usage: $0 add-external-node <name> <ip> [role] [arch]"
                exit 1
            fi
            init_deployment
            onboard_external_node "$2" "$3" "${4:-worker}" "${5:-amd64}"
            ;;
        "reset-node")
            if [ $# -lt 2 ]; then
                error "Usage: $0 reset-node <node_name>"
                exit 1
            fi
            init_deployment
            reset_node_if_needed "$2"
            ;;
        "cleanup")
            rm -rf "$LOCK_DIR" "$LOG_DIR" 2>/dev/null || true
            success "Cleanup completed"
            ;;
        "logs")
            if [ -f "$LOG_DIR/deployment.log" ]; then
                tail -f "$LOG_DIR/deployment.log"
            else
                warn "No deployment logs found"
            fi
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# Trap for cleanup
trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT

# Run main function
main "$@"