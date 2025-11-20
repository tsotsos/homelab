# =============================================================================
# CONFIGURATION FILE OUTPUTS
# =============================================================================

output "talos_config_path" {
  description = "Path to the Talos client configuration file"
  value       = "${path.module}/talos-config/talosconfig"
}

output "kubeconfig_path" {
  description = "Path to the Kubernetes configuration file"
  value       = length(local.control_plane_nodes) > 0 ? "${path.module}/talos-config/kubeconfig" : null
}

output "cluster_config_directory" {
  description = "Directory containing all Talos and Kubernetes configuration files"
  value       = "${path.module}/talos-config/"
}

# =============================================================================
# CLUSTER INFORMATION OUTPUTS
# =============================================================================

output "cluster_name" {
  description = "Name of the deployed Talos cluster"
  value       = local.cluster_config.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint URL"
  value       = local.cluster_config.endpoint
}

output "cluster_vip" {
  description = "Virtual IP address for control plane load balancing"
  value       = local.cluster_config.vip
}

# =============================================================================
# CONTROL PLANE OUTPUTS
# =============================================================================

output "control_plane_ips" {
  description = "List of IP addresses assigned to control plane nodes"
  value       = local.control_plane_ips
}

output "control_plane_nodes" {
  description = "Detailed information about control plane nodes"
  value = {
    for key, node in local.control_plane_nodes : key => {
      name         = node.name
      vm_id        = node.vm_id
      ip_address   = node.ip_address
      proxmox_node = node.proxmox_node
      role         = node.role
    }
  }
}

output "control_plane_vm_ids" {
  description = "Proxmox VM IDs for all control plane nodes"
  value = {
    for key, vm in proxmox_virtual_environment_vm.control_plane : key => vm.vm_id
  }
}

# =============================================================================
# WORKER NODE OUTPUTS
# =============================================================================

output "worker_ips" {
  description = "List of IP addresses assigned to worker nodes"
  value       = local.worker_ips
}

output "worker_nodes" {
  description = "Detailed information about worker nodes"
  value = {
    for key, node in local.worker_nodes : key => {
      name         = node.name
      vm_id        = node.vm_id
      ip_address   = node.ip_address
      proxmox_node = node.proxmox_node
      role         = node.role
    }
  }
}

output "worker_vm_ids" {
  description = "Proxmox VM IDs for all worker nodes"
  value = {
    for key, vm in proxmox_virtual_environment_vm.worker : key => vm.vm_id
  }
}

# =============================================================================
# NETWORK INFORMATION OUTPUTS
# =============================================================================

output "network_configuration" {
  description = "Network configuration details for the cluster"
  value = {
    subnet_cidr = local.network_config.subnet_cidr
    gateway     = local.network_config.gateway
    dns_servers = local.network_config.dns_servers
    vip_address = local.network_config.vip_address
  }
}

# =============================================================================
# DEPLOYMENT SUMMARY OUTPUT
# =============================================================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    cluster = {
      name               = local.cluster_config.name
      endpoint           = local.cluster_config.endpoint
      talos_version      = local.versions_config.talos
      kubernetes_version = local.versions_config.kubernetes
    }
    nodes = {
      control_plane_count = length(local.control_plane_nodes)
      worker_count        = length(local.worker_nodes)
      total_nodes         = length(local.control_plane_nodes) + length(local.worker_nodes)
    }
    proxmox = {
      nodes_used = local.proxmox_config.nodes
      vm_bridge  = local.network_config_yaml.bridge
      storage = {
        primary   = local.proxmox_config.storage.primary
        secondary = local.proxmox_config.storage.secondary
      }
    }
  }
}

# =============================================================================
# BOOTSTRAP INSTRUCTIONS OUTPUT
# =============================================================================

output "bootstrap_instructions" {
  description = "Step-by-step instructions for bootstrapping the Talos cluster"
  value       = <<-EOT
    
    ╔════════════════════════════════════════════════════════════════════════════════╗
    ║                         TALOS CLUSTER BOOTSTRAP GUIDE                         ║
    ╚════════════════════════════════════════════════════════════════════════════════╝
    
    Your Talos Kubernetes cluster has been provisioned! Follow these steps to complete the setup:
    
    📋 CLUSTER INFORMATION:
    ────────────────────────────────────────────────────────────────────────────────
    • Cluster Name:     ${local.cluster_config.name}
    • API Endpoint:     ${local.cluster_config.endpoint}
    • Control Plane IP: ${local.cluster_config.vip}
    • Node Count:       ${length(local.control_plane_nodes)} control plane + ${length(local.worker_nodes)} workers
    
    🚀 BOOTSTRAP STEPS:
    ────────────────────────────────────────────────────────────────────────────────
    
    1. Wait for all VMs to boot and become accessible:
       for ip in ${join(" ", local.control_plane_ips)}; do
         until ping -c1 $$ip >/dev/null 2>&1; do sleep 5; done
         echo "✓ $$ip is responding"
       done
    
    2. Set the Talos configuration:
       export TALOSCONFIG="${path.module}/talos-config/talosconfig"
    
    3. Bootstrap the first control plane node:
       talosctl bootstrap \\
         --nodes ${local.control_plane_ips[0]} \\
         --endpoints ${join(",", local.control_plane_ips)}
    
    4. Wait for the cluster to become ready:
       talosctl health \\
         --nodes ${join(",", local.control_plane_ips)} \\
         --endpoints ${join(",", local.control_plane_ips)}
    
    5. Retrieve the kubeconfig:
       talosctl kubeconfig \\
         --nodes ${local.control_plane_ips[0]} \\
         --endpoints ${join(",", local.control_plane_ips)} \\
         --file "${path.module}/talos-config/kubeconfig"
    
    6. Verify cluster status:
       export KUBECONFIG="${path.module}/talos-config/kubeconfig"
       kubectl get nodes -o wide
       kubectl get pods -A
    
    📁 CONFIGURATION FILES:
    ────────────────────────────────────────────────────────────────────────────────
    • Talos Config: ${path.module}/talos-config/talosconfig
    • Kubeconfig:   ${path.module}/talos-config/kubeconfig
    • Node Configs: ${path.module}/talos-config/controlplane-*.yaml
    •               ${path.module}/talos-config/worker-*.yaml
    
    🔧 USEFUL COMMANDS:
    ────────────────────────────────────────────────────────────────────────────────
    • Check node status: talosctl get members
    • View system logs:   talosctl logs --follow
    • Apply patches:      talosctl patch mc --patch @patch.yaml
    • Upgrade nodes:      talosctl upgrade --image ghcr.io/siderolabs/installer:vX.Y.Z
    
    📖 For more information, visit: https://www.talos.dev/latest/introduction/
    
  EOT
}

# =============================================================================
# QUICK COMMANDS OUTPUT
# =============================================================================

output "quick_commands" {
  description = "Ready-to-use commands for cluster management"
  value = {
    set_talosconfig = "export TALOSCONFIG='${path.module}/talos-config/talosconfig'"
    set_kubeconfig  = "export KUBECONFIG='${path.module}/talos-config/kubeconfig'"
    bootstrap_cluster = join(" ", [
      "talosctl bootstrap",
      "--nodes ${local.control_plane_ips[0]}",
      "--endpoints ${join(",", local.control_plane_ips)}"
    ])
    health_check = join(" ", [
      "talosctl health",
      "--nodes ${join(",", local.control_plane_ips)}",
      "--endpoints ${join(",", local.control_plane_ips)}"
    ])
    get_kubeconfig = join(" ", [
      "talosctl kubeconfig",
      "--nodes ${local.control_plane_ips[0]}",
      "--endpoints ${join(",", local.control_plane_ips)}",
      "--file '${path.module}/talos-config/kubeconfig'"
    ])
  }
}