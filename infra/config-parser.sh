#!/bin/bash
# =============================================================================
# CLUSTER CONFIGURATION PARSER
# =============================================================================
# Provides functions to parse and access the cluster-config.yaml file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/cluster-config.yaml"

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "ERROR: yq is required but not installed. Install with: brew install yq" >&2
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE" >&2
    exit 1
fi

# =============================================================================
# CONFIGURATION ACCESS FUNCTIONS
# =============================================================================

# Get cluster configuration
get_cluster_name() {
    yq '.cluster.name' "$CONFIG_FILE"
}

get_cluster_endpoint() {
    yq '.cluster.endpoint' "$CONFIG_FILE"
}

get_cluster_vip() {
    yq '.cluster.vip' "$CONFIG_FILE"
}

get_cluster_cni() {
    yq '.cluster.cni' "$CONFIG_FILE"
}

# Get network configuration
get_network_gateway() {
    yq '.network.gateway' "$CONFIG_FILE"
}

get_network_dns_servers() {
    yq -r '.network.dns_servers[]' "$CONFIG_FILE"
}

get_network_bridge() {
    yq '.network.bridge' "$CONFIG_FILE"
}

# Get version information
get_talos_version() {
    yq '.versions.talos' "$CONFIG_FILE"
}

get_kubernetes_version() {
    yq '.versions.kubernetes' "$CONFIG_FILE"
}

# Get node lists
get_control_plane_nodes() {
    yq -r '.nodes | to_entries[] | select(.value.role == "controlplane") | .key' "$CONFIG_FILE"
}

get_worker_nodes() {
    yq -r '.nodes | to_entries[] | select(.value.role == "worker") | .key' "$CONFIG_FILE"
}

get_all_nodes() {
    yq -r '.nodes | to_entries[] | .key' "$CONFIG_FILE"
}

# Get node specific information
get_node_ip() {
    local node_name=$1
    yq ".nodes.\"$node_name\".ip_address" "$CONFIG_FILE"
}

get_node_role() {
    local node_name=$1
    yq ".nodes.\"$node_name\".role" "$CONFIG_FILE"
}

get_node_vm_id() {
    local node_name=$1
    yq ".nodes.\"$node_name\".vm_id" "$CONFIG_FILE"
}

get_node_mac_address() {
    local node_name=$1
    yq ".nodes.\"$node_name\".mac_address" "$CONFIG_FILE"
}

get_node_proxmox_node() {
    local node_name=$1
    yq ".nodes.\"$node_name\".proxmox_node" "$CONFIG_FILE"
}

# Get node resource overrides
get_node_memory() {
    local node_name=$1
    local role=$(get_node_role "$node_name")
    
    # Check for node-specific override first
    local node_memory=$(yq ".nodes.\"$node_name\".memory_mb // null" "$CONFIG_FILE")
    if [ "$node_memory" != "null" ]; then
        echo "$node_memory"
        return
    fi
    
    # Check for role-specific default
    local role_memory=$(yq ".defaults.$role.memory_mb // null" "$CONFIG_FILE")
    if [ "$role_memory" != "null" ]; then
        echo "$role_memory"
        return
    fi
    
    # Fall back to global default
    yq '.defaults.vm.memory_mb' "$CONFIG_FILE"
}

get_node_cpu_cores() {
    local node_name=$1
    
    # Check for node-specific override first
    local node_cpu=$(yq ".nodes.\"$node_name\".cpu_cores // null" "$CONFIG_FILE")
    if [ "$node_cpu" != "null" ]; then
        echo "$node_cpu"
        return
    fi
    
    # Fall back to global default
    yq '.defaults.vm.cpu_cores' "$CONFIG_FILE"
}

get_node_disk_size() {
    local node_name=$1
    local role=$(get_node_role "$node_name")
    
    # Check for node-specific override first
    local node_disk=$(yq ".nodes.\"$node_name\".disk_size // null" "$CONFIG_FILE")
    if [ "$node_disk" != "null" ]; then
        echo "$node_disk"
        return
    fi
    
    # Check for role-specific default
    local role_disk=$(yq ".defaults.$role.disk_size // null" "$CONFIG_FILE")
    if [ "$role_disk" != "null" ]; then
        echo "$role_disk"
        return
    fi
    
    # Fall back to global default
    yq '.defaults.vm.disk_size' "$CONFIG_FILE"
}

get_node_etcd_disk() {
    local node_name=$1
    local role=$(get_node_role "$node_name")
    
    if [ "$role" != "controlplane" ]; then
        echo "null"
        return
    fi
    
    # Check for node-specific override first
    local node_etcd=$(yq ".nodes.\"$node_name\".etcd_disk_gb // null" "$CONFIG_FILE")
    if [ "$node_etcd" != "null" ]; then
        echo "$node_etcd"
        return
    fi
    
    # Fall back to control plane default
    yq '.defaults.control_plane.etcd_disk_gb' "$CONFIG_FILE"
}

get_node_storage_disk() {
    local node_name=$1
    local role=$(get_node_role "$node_name")
    
    if [ "$role" != "worker" ]; then
        echo "null"
        return
    fi
    
    # Check for node-specific override first
    local node_storage=$(yq ".nodes.\"$node_name\".storage_disk_gb // null" "$CONFIG_FILE")
    if [ "$node_storage" != "null" ]; then
        echo "$node_storage"
        return
    fi
    
    # Fall back to worker default
    yq '.defaults.worker.storage_disk_gb' "$CONFIG_FILE"
}

# Get deployment configuration
get_deployment_parallel_enabled() {
    yq '.deployment.parallel.enabled' "$CONFIG_FILE"
}

get_deployment_max_concurrent() {
    yq '.deployment.parallel.max_concurrent_nodes' "$CONFIG_FILE"
}

get_deployment_timeout() {
    local timeout_type=$1
    yq ".deployment.timeouts.$timeout_type" "$CONFIG_FILE"
}

# Get proxmox configuration
get_proxmox_endpoint() {
    yq '.proxmox.endpoint' "$CONFIG_FILE"
}

get_proxmox_nodes() {
    yq -r '.proxmox.nodes[]' "$CONFIG_FILE"
}

get_proxmox_storage_primary() {
    yq '.proxmox.storage.primary' "$CONFIG_FILE"
}

get_proxmox_storage_secondary() {
    yq '.proxmox.storage.secondary' "$CONFIG_FILE"
}

# Generate node maps for scripts
generate_node_map() {
    echo "# Node IP mappings (generated from cluster-config.yaml)"
    
    for node in $(get_all_nodes); do
        local ip=$(get_node_ip "$node")
        local var_name=$(echo "$node" | tr '-' '_')
        echo "NODE_${var_name}=\"$ip\""
    done
}

# Generate terraform locals
generate_terraform_locals() {
    cat << 'EOF'
# Generated from cluster-config.yaml - do not edit manually
locals {
  # Import YAML configuration
  cluster_config_raw = yamldecode(file("${path.module}/cluster-config.yaml"))
  
  # Cluster configuration
  cluster_name = local.cluster_config_raw.cluster.name
  cluster_endpoint = local.cluster_config_raw.cluster.endpoint
  cluster_vip = local.cluster_config_raw.cluster.vip
  
  # Node configurations from YAML
  yaml_nodes = {
    for name, config in local.cluster_config_raw.nodes : name => {
      vm_id = config.vm_id
      ip_address = config.ip_address
      mac_address = config.mac_address
      proxmox_node = config.proxmox_node
      role = config.role
      memory_mb = try(
        config.memory_mb,
        local.cluster_config_raw.defaults[config.role].memory_mb,
        local.cluster_config_raw.defaults.vm.memory_mb
      )
      cpu_cores = try(
        config.cpu_cores,
        local.cluster_config_raw.defaults.vm.cpu_cores
      )
      disk_size = try(
        config.disk_size,
        local.cluster_config_raw.defaults[config.role].disk_size,
        local.cluster_config_raw.defaults.vm.disk_size
      )
      etcd_disk_gb = config.role == "controlplane" ? try(
        config.etcd_disk_gb,
        local.cluster_config_raw.defaults.control_plane.etcd_disk_gb
      ) : null
      storage_disk_gb = config.role == "worker" ? try(
        config.storage_disk_gb,
        local.cluster_config_raw.defaults.worker.storage_disk_gb
      ) : null
    }
  }
}
EOF
}

# Main function for CLI usage
main() {
    case "${1:-help}" in
        "cluster-name")
            get_cluster_name
            ;;
        "cluster-vip")
            get_cluster_vip
            ;;
        "control-plane-nodes")
            get_control_plane_nodes
            ;;
        "worker-nodes")
            get_worker_nodes
            ;;
        "node-ip")
            get_node_ip "$2"
            ;;
        "node-memory")
            get_node_memory "$2"
            ;;
        "generate-node-map")
            generate_node_map
            ;;
        "generate-terraform")
            generate_terraform_locals
            ;;
        "help"|*)
            echo "Usage: $0 <command> [args]"
            echo "Commands:"
            echo "  cluster-name                    - Get cluster name"
            echo "  cluster-vip                     - Get cluster VIP"
            echo "  control-plane-nodes             - List control plane nodes"
            echo "  worker-nodes                    - List worker nodes"
            echo "  node-ip <node_name>             - Get node IP"
            echo "  node-memory <node_name>         - Get node memory"
            echo "  generate-node-map               - Generate bash node mappings"
            echo "  generate-terraform              - Generate Terraform locals"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi