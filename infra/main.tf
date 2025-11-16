# =============================================================================
# PROVIDERS
# =============================================================================

provider "proxmox" {
  endpoint  = var.proxmox_ve_endpoint
  api_token = var.proxmox_ve_api_token
  insecure  = var.proxmox_ve_insecure
  ssh {
    agent    = true
    username = var.proxmox_ve_ssh_username
  }
}

provider "talos" {}

# =============================================================================
# LOCAL VALUES
# =============================================================================

locals {
  # Network configuration
  network_config = {
    subnet_cidr = "10.0.2.0/24"
    gateway     = var.network_gateway
    dns_servers = var.dns_servers
    vip_address = var.cluster_vip
  }

  # Cluster configuration
  cluster_config = {
    name              = var.cluster_name
    endpoint          = var.cluster_endpoint
    talos_version     = var.talos_version
    kubernetes_version = var.kubernetes_version
  }

  # VM configuration templates
  vm_defaults = {
    cpu = {
      cores   = var.vm_cpu_cores
      sockets = 1
      type    = "host"
    }
    memory = {
      dedicated = var.vm_memory
    }
    disk = {
      interface = "virtio0"
      size      = parseint(regex("(\\d+)", var.vm_disk_size)[0], 10)
      format    = "raw"
      datastore_id = var.vm_storage
    }
    network = {
      bridge    = var.vm_bridge
      vlan_id   = var.vm_vlan_id
    }
  }

  # Function to get VM configuration for a specific node
  get_vm_config = {
    for node_key, node in merge(local.control_plane_nodes, local.worker_nodes) : node_key => {
      memory_mb = lookup(var.per_vm_config, node.name, {}).memory_mb != null ? (
        lookup(var.per_vm_config, node.name, {}).memory_mb
      ) : (
        node.role == "controlplane" && var.control_plane_memory != null ? var.control_plane_memory : (
          node.role == "worker" && var.worker_memory != null ? var.worker_memory : var.vm_memory
        )
      )
      
      cpu_cores = lookup(var.per_vm_config, node.name, {}).cpu_cores != null ? (
        lookup(var.per_vm_config, node.name, {}).cpu_cores
      ) : var.vm_cpu_cores
      
      disk_size = lookup(var.per_vm_config, node.name, {}).disk_size != null ? (
        lookup(var.per_vm_config, node.name, {}).disk_size
      ) : (
        node.role == "controlplane" && var.control_plane_disk_size != null ? var.control_plane_disk_size : (
          node.role == "worker" && var.worker_disk_size != null ? var.worker_disk_size : var.vm_disk_size
        )
      )
      
      etcd_disk_gb = lookup(var.per_vm_config, node.name, {}).etcd_disk_gb != null ? (
        lookup(var.per_vm_config, node.name, {}).etcd_disk_gb
      ) : (
        node.role == "controlplane" ? var.control_plane_etcd_disk_size : null
      )
      
      storage_disk_gb = lookup(var.per_vm_config, node.name, {}).storage_disk_gb != null ? (
        lookup(var.per_vm_config, node.name, {}).storage_disk_gb
      ) : (
        node.role == "worker" ? var.worker_storage_disk_size : null
      )
    }
  }

  # Generate control plane nodes configuration
  control_plane_nodes = {
    for i in range(var.control_plane_count) : "cp-${i + 1}" => {
      name         = "kng-cp-${i + 1}"
      vm_id        = 800 + i + 1
      ip_address   = "10.0.2.${101 + i}"  # Updated for DHCP reservations: 10.0.2.101-103
      proxmox_node = var.proxmox_nodes[i % length(var.proxmox_nodes)]
      role         = "controlplane"
      index        = i
      mac_address  = length(var.control_plane_mac_addresses) > i ? var.control_plane_mac_addresses[i] : null
    }
  }

  # Generate worker nodes configuration
  worker_nodes = {
    for i in range(var.worker_count_per_proxmox_node * length(var.proxmox_nodes)) : "worker-${i + 1}" => {
      name         = "kng-worker-${i + 1}"
      vm_id        = 810 + i + 1
      ip_address   = "10.0.2.${104 + i}"  # Updated for DHCP reservations: 10.0.2.104-109
      proxmox_node = var.proxmox_nodes[i % length(var.proxmox_nodes)]
      role         = "worker"
      index        = i
      mac_address  = length(var.worker_mac_addresses) > i ? var.worker_mac_addresses[i] : null
    }
  }

  # Combined nodes for easier iteration
  all_nodes = merge(local.control_plane_nodes, local.worker_nodes)

  # Extract IPs for easier reference
  control_plane_ips = [for node in local.control_plane_nodes : node.ip_address]
  worker_ips       = [for node in local.worker_nodes : node.ip_address]
  all_ips          = [for node in local.all_nodes : node.ip_address]
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# No data sources needed for ISO installation

# =============================================================================
# TALOS CONFIGURATION
# =============================================================================

# Generate Talos machine secrets
resource "talos_machine_secrets" "cluster_secrets" {}

# Generate Talos client configuration
data "talos_client_configuration" "cluster_client_config" {
  cluster_name         = local.cluster_config.name
  client_configuration = talos_machine_secrets.cluster_secrets.client_configuration
  endpoints            = local.control_plane_ips
}

# Control plane machine configurations
data "talos_machine_configuration" "control_plane" {
  for_each = local.control_plane_nodes

  cluster_name     = local.cluster_config.name
  cluster_endpoint = local.cluster_config.endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.cluster_secrets.machine_secrets
  talos_version    = local.cluster_config.talos_version
  kubernetes_version = local.cluster_config.kubernetes_version

  config_patches = [
    yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = var.allow_scheduling_on_control_planes
        network = {
          cni = {
            name = var.cluster_cni
          }
        }
        controlPlane = {
          endpoint = local.cluster_config.endpoint
        }
        apiServer = {
          certSANs = [
            local.network_config.vip_address,
            each.value.ip_address
          ]
        }
        etcd = {
          advertisedSubnets = [local.network_config.subnet_cidr]
        }
      }
      machine = {
        certSANs = [
          local.network_config.vip_address,
          each.value.ip_address
        ]
        network = {
          hostname = each.value.name
          interfaces = [
            {
              interface = "ens18"
              dhcp      = true  # Use DHCP instead of static IP
              vip = each.value.index == 0 ? {
                ip = local.network_config.vip_address
              } : null
            }
          ]
          nameservers = local.network_config.dns_servers
        }
        install = {
          disk       = var.talos_install_disk
          image      = "ghcr.io/siderolabs/installer:${local.cluster_config.talos_version}"
          wipe       = true
          bootloader = true
        }
        disks = [
          {
            device = "/dev/vdb"
            partitions = [
              {
                mountpoint = "/var/lib/etcd"
              }
            ]
          }
        ]
        features = {
          rbac           = true
          stableHostname = true
          apidCheckExtKeyUsage = true
          diskQuotaSupport     = true
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        sysctls = var.control_plane_sysctls
        kubelet = {
          image = "ghcr.io/siderolabs/kubelet:${local.cluster_config.kubernetes_version}"
          extraArgs = var.control_plane_kubelet_extra_args
          disableManifestsDirectory = false
        }
      }
    }),
    var.ssh_public_key != "" ? yamlencode({
      machine = {
        files = [
          {
            content     = var.ssh_public_key
            path        = "/var/home/root/.ssh/authorized_keys"
            permissions = 384  # 0600 in octal = 384 in decimal
            op          = "create"
          }
        ]
      }
    }) : ""
  ]
}

# Worker machine configurations
data "talos_machine_configuration" "worker" {
  for_each = local.worker_nodes

  cluster_name       = local.cluster_config.name
  cluster_endpoint   = local.cluster_config.endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster_secrets.machine_secrets
  talos_version      = local.cluster_config.talos_version
  kubernetes_version = local.cluster_config.kubernetes_version

  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = each.value.name
          interfaces = [
            {
              interface = "ens18"
              dhcp      = true  # Use DHCP instead of static IP
            }
          ]
          nameservers = local.network_config.dns_servers
        }
        install = {
          disk       = var.talos_install_disk
          image      = "ghcr.io/siderolabs/installer:${local.cluster_config.talos_version}"
          wipe       = true
          bootloader = true
        }
        features = {
          rbac               = true
          stableHostname     = true
          apidCheckExtKeyUsage = true
          diskQuotaSupport   = true
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        sysctls = var.worker_sysctls
        kubelet = {
          image = "ghcr.io/siderolabs/kubelet:${local.cluster_config.kubernetes_version}"
          extraArgs = var.worker_kubelet_extra_args
        }
      }
    }),
    var.ssh_public_key != "" ? yamlencode({
      machine = {
        files = [
          {
            content = var.ssh_public_key
            path    = "/var/home/root/.ssh/authorized_keys"
            permissions = 384  # 0600 in octal = 384 in decimal
            op      = "create"
          }
        ]
      }
    }) : ""
  ]
}

# =============================================================================
# LOCAL FILES
# =============================================================================

# Create configuration directory
resource "local_file" "talos_config_dir" {
  content  = "# Talos configuration directory\n"
  filename = "${path.module}/talos-config/.gitkeep"
}

# Save Talos client configuration
resource "local_file" "talosconfig" {
  content         = data.talos_client_configuration.cluster_client_config.talos_config
  filename        = "${path.module}/talos-config/talosconfig"
  file_permission = "0600"
  
  depends_on = [local_file.talos_config_dir]
}

# Save control plane machine configurations
resource "local_file" "control_plane_configs" {
  for_each = local.control_plane_nodes

  content         = data.talos_machine_configuration.control_plane[each.key].machine_configuration
  filename        = "${path.module}/talos-config/controlplane-${each.value.name}.yaml"
  file_permission = "0600"
  
  depends_on = [local_file.talos_config_dir]
}

# Save worker machine configurations
resource "local_file" "worker_configs" {
  for_each = local.worker_nodes

  content         = data.talos_machine_configuration.worker[each.key].machine_configuration
  filename        = "${path.module}/talos-config/worker-${each.value.name}.yaml"
  file_permission = "0600"
  
  depends_on = [local_file.talos_config_dir]
}

# =============================================================================
# PROXMOX VIRTUAL MACHINES
# =============================================================================

# Control plane VMs
resource "proxmox_virtual_environment_vm" "control_plane" {
  for_each = local.control_plane_nodes

  name        = each.value.name
  description = "Talos Kubernetes Control Plane Node ${each.value.index + 1}"
  tags        = ["kubernetes", "talos", "control-plane"]
  node_name   = each.value.proxmox_node
  vm_id       = each.value.vm_id
  
  started = true
  on_boot = true

  # Boot from disk first, then CD-ROM (after installation)
  boot_order = ["virtio0", "ide2"]

  # Add Talos ISO to CD-ROM
  cdrom {
    file_id   = var.talos_iso_file_id
    interface = "ide2"
  }

  cpu {
    cores   = local.get_vm_config[each.key].cpu_cores
    sockets = local.vm_defaults.cpu.sockets
    type    = local.vm_defaults.cpu.type
  }

  memory {
    dedicated = local.get_vm_config[each.key].memory_mb
  }

  network_device {
    bridge      = local.vm_defaults.network.bridge
    vlan_id     = local.vm_defaults.network.vlan_id
    mac_address = length(var.control_plane_mac_addresses) > each.value.index ? var.control_plane_mac_addresses[each.value.index] : null
  }

  disk {
    datastore_id = local.vm_defaults.disk.datastore_id
    interface    = local.vm_defaults.disk.interface
    size         = parseint(regex("(\\d+)", local.get_vm_config[each.key].disk_size)[0], 10)
    file_format  = local.vm_defaults.disk.format
  }

  # Additional disk for etcd data
  disk {
    datastore_id = var.vm_storage_secondary
    file_format  = "raw"
    interface    = "virtio1"
    size         = local.get_vm_config[each.key].etcd_disk_gb
  }

  operating_system {
    type = "l26"
  }

  # Talos will be configured via machine config, not cloud-init
  lifecycle {
    ignore_changes = [
      cdrom,
    ]
  }
}

# Worker VMs
resource "proxmox_virtual_environment_vm" "worker" {
  for_each = local.worker_nodes

  name        = each.value.name
  description = "Talos Kubernetes Worker Node ${each.value.index + 1}"
  tags        = ["kubernetes", "talos", "worker"]
  node_name   = each.value.proxmox_node
  vm_id       = each.value.vm_id
  
  started = true
  on_boot = true

  # Boot from disk first, then CD-ROM (after installation)
  boot_order = ["virtio0", "ide2"]

  # Add Talos ISO to CD-ROM
  cdrom {
    file_id   = var.talos_iso_file_id
    interface = "ide2"
  }

  cpu {
    cores   = local.get_vm_config[each.key].cpu_cores
    sockets = local.vm_defaults.cpu.sockets
    type    = local.vm_defaults.cpu.type
  }

  memory {
    dedicated = local.get_vm_config[each.key].memory_mb
  }

  network_device {
    bridge      = local.vm_defaults.network.bridge
    vlan_id     = local.vm_defaults.network.vlan_id
    mac_address = length(var.worker_mac_addresses) > each.value.index ? var.worker_mac_addresses[each.value.index] : null
  }

  disk {
    datastore_id = local.vm_defaults.disk.datastore_id
    interface    = local.vm_defaults.disk.interface
    size         = parseint(regex("(\\d+)", local.get_vm_config[each.key].disk_size)[0], 10)
    file_format  = local.vm_defaults.disk.format
  }

  # Additional disk for container storage
  disk {
    datastore_id = var.vm_storage_secondary
    file_format  = "raw"
    interface    = "virtio1"
    size         = local.get_vm_config[each.key].storage_disk_gb
  }

  operating_system {
    type = "l26"
  }

  # Talos will be configured via machine config, not cloud-init
  lifecycle {
    ignore_changes = [
      cdrom,
    ]
  }
}

# =============================================================================
# KUBERNETES CONFIGURATION
# =============================================================================

# Note: Kubeconfig is retrieved manually after cluster bootstrap
# Use: talosctl kubeconfig --nodes 10.0.2.101 --endpoints 10.0.2.101,10.0.2.102,10.0.2.103 --file './talos-config/kubeconfig'
# resource "talos_cluster_kubeconfig" "cluster_kubeconfig" {
#   count = var.control_plane_count > 0 ? 1 : 0
#   
#   client_configuration = talos_machine_secrets.cluster_secrets.client_configuration
#   node                 = local.control_plane_ips[0]
#   
#   depends_on = [
#     proxmox_virtual_environment_vm.control_plane,
#   ]
# }

# Note: Kubeconfig is created manually after cluster bootstrap
# resource "local_file" "kubeconfig" {
#   count = var.control_plane_count > 0 ? 1 : 0
#   
#   content         = talos_cluster_kubeconfig.cluster_kubeconfig[0].kubeconfig_raw
#   filename        = "${path.module}/talos-config/kubeconfig"
#   file_permission = "0600"
#   
#   depends_on = [local_file.talos_config_dir]
# }
