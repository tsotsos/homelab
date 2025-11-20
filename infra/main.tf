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
  # Load configuration from YAML file
  cluster_config_yaml = yamldecode(file("${path.module}/cluster-config.yaml"))

  # Extract configuration from YAML
  cluster_config      = local.cluster_config_yaml.cluster
  versions_config     = local.cluster_config_yaml.versions
  network_config_yaml = local.cluster_config_yaml.network
  proxmox_config      = local.cluster_config_yaml.proxmox
  defaults_config     = local.cluster_config_yaml.defaults

  # Make defaults available as 'defaults' local
  defaults = local.defaults_config

  # SSH configuration from YAML
  ssh_config = local.cluster_config_yaml.ssh

  # Network configuration from YAML
  network_config = {
    subnet_cidr = "${local.network_config_yaml.gateway}/${local.network_config_yaml.cidr}"
    gateway     = local.network_config_yaml.gateway
    dns_servers = local.network_config_yaml.dns_servers
    vip_address = local.cluster_config.vip
  }

  # VM configuration templates from YAML defaults
  vm_defaults = {
    cpu = {
      cores   = local.defaults_config.vm.cpu_cores
      sockets = 1
      type    = "host"
    }
    memory = {
      dedicated = local.defaults_config.vm.memory_mb
    }
    disk = {
      interface    = "virtio0"
      size         = parseint(regex("(\\d+)", local.defaults_config.vm.disk_size)[0], 10)
      format       = "raw"
      datastore_id = local.proxmox_config.storage.primary
    }
    network = {
      bridge  = local.network_config_yaml.bridge
      vlan_id = local.network_config_yaml.vlan_id
    }
  }

  # Extract nodes from YAML configuration
  yaml_nodes = local.cluster_config_yaml.nodes

  # Function to get VM configuration for a specific node from YAML
  get_vm_config = {
    for node_name, node_config in local.yaml_nodes : node_name => {
      memory_mb = try(node_config.memory_mb, null) != null ? (
        node_config.memory_mb
        ) : (
        node_config.role == "controlplane" ? local.defaults_config.control_plane.memory_mb : local.defaults_config.worker.memory_mb
      )

      cpu_cores = try(node_config.cpu_cores, null) != null ? (
        node_config.cpu_cores
      ) : local.defaults_config.vm.cpu_cores

      disk_size = try(node_config.disk_size, null) != null ? (
        node_config.disk_size
        ) : (
        node_config.role == "controlplane" ? local.defaults_config.control_plane.disk_size : local.defaults_config.worker.disk_size
      )

      etcd_disk_gb = try(node_config.etcd_disk_gb, null) != null ? (
        node_config.etcd_disk_gb
        ) : (
        node_config.role == "controlplane" ? local.defaults_config.control_plane.etcd_disk_gb : null
      )

      storage_disk_gb = try(node_config.storage_disk_gb, null) != null ? (
        node_config.storage_disk_gb
        ) : (
        node_config.role == "worker" ? local.defaults_config.worker.storage_disk_gb : null
      )
    }
  }

  # Generate control plane nodes from YAML
  control_plane_nodes_list = [for node_name, node_config in local.yaml_nodes : merge(node_config, {
    name = node_name
  }) if node_config.role == "controlplane"]

  control_plane_nodes = {
    for idx, node in local.control_plane_nodes_list : node.name => merge(node, {
      index = idx
    })
  }

  # Generate worker nodes from YAML  
  worker_nodes_list = [for node_name, node_config in local.yaml_nodes : merge(node_config, {
    name = node_name
  }) if node_config.role == "worker"]

  worker_nodes = {
    for idx, node in local.worker_nodes_list : node.name => merge(node, {
      index = idx
    })
  }

  # Combined nodes for easier iteration
  all_nodes = local.yaml_nodes

  # Extract IPs for easier reference
  control_plane_ips = [for node_name, node in local.control_plane_nodes : node.ip_address]
  worker_ips        = [for node_name, node in local.worker_nodes : node.ip_address]
  all_ips           = [for node in local.all_nodes : node.ip_address]
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

  cluster_name       = local.cluster_config.name
  cluster_endpoint   = local.cluster_config.endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.cluster_secrets.machine_secrets
  talos_version      = local.versions_config.talos
  kubernetes_version = local.versions_config.kubernetes

  config_patches = [
    yamlencode({
      cluster = merge({
        allowSchedulingOnControlPlanes = false # Set in YAML if needed
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
        # CNI configuration - explicitly disable if set to "none"
        network = {
          cni = {
            name = local.cluster_config.cni
          }
        }
      })
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
              dhcp      = !local.cluster_config.use_static_ips
              addresses = local.cluster_config.use_static_ips ? ["${each.value.ip_address}/${local.network_config_yaml.cidr}"] : null
              routes = local.cluster_config.use_static_ips ? [{
                network = "0.0.0.0/0"
                gateway = local.network_config.gateway
              }] : null
              vip = local.cluster_config.use_talos_vip && each.value.index == 0 ? {
                ip = local.network_config.vip_address
              } : null
            }
          ]
          nameservers = local.network_config.dns_servers
        }
        install = {
          disk            = local.defaults.talos.install_disk
          image           = "${local.versions_config.talos_installer}"
          wipe            = true
          bootloader      = true
          extraKernelArgs = local.defaults.talos.kernel_args
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
          rbac                 = true
          stableHostname       = true
          apidCheckExtKeyUsage = true
          diskQuotaSupport     = true
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        sysctls = local.defaults.talos.sysctls
        kubelet = {
          image                     = "ghcr.io/siderolabs/kubelet:${local.versions_config.kubernetes}"
          extraArgs                 = local.defaults.talos.kubelet_extra_args
          disableManifestsDirectory = false
        }
        nodeLabels = try(local.yaml_nodes[each.key].labels, {})
      }
    }),
    local.ssh_config.public_key != "" ? yamlencode({
      machine = {
        files = [
          {
            content     = local.ssh_config.public_key
            path        = "/var/home/root/.ssh/authorized_keys"
            permissions = 384 # 0600 in octal = 384 in decimal
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
  talos_version      = local.versions_config.talos
  kubernetes_version = local.versions_config.kubernetes

  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = each.value.name
          interfaces = [
            {
              interface = "ens18"
              dhcp      = !local.cluster_config.use_static_ips
              addresses = local.cluster_config.use_static_ips ? ["${each.value.ip_address}/${local.network_config_yaml.cidr}"] : null
              routes = local.cluster_config.use_static_ips ? [{
                network = "0.0.0.0/0"
                gateway = local.network_config.gateway
              }] : null
            }
          ]
          nameservers = local.network_config.dns_servers
        }
        install = {
          disk            = local.defaults.talos.install_disk
          image           = "${local.versions_config.talos_installer}"
          wipe            = true
          bootloader      = true
          extraKernelArgs = local.defaults.talos.kernel_args
        }
        disks = local.get_vm_config[each.key].storage_disk_gb != null && local.get_vm_config[each.key].storage_disk_gb > 0 ? [
          {
            device = "/dev/vdb"
            partitions = [
              {
                mountpoint = "/var/lib/longhorn"
              }
            ]
          }
        ] : []
        features = {
          rbac                 = true
          stableHostname       = true
          apidCheckExtKeyUsage = true
          diskQuotaSupport     = true
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        sysctls = local.defaults.talos.sysctls
        kubelet = {
          image     = "ghcr.io/siderolabs/kubelet:${local.versions_config.kubernetes}"
          extraArgs = local.defaults.talos.kubelet_extra_args
        }
        nodeLabels = try(local.yaml_nodes[each.key].labels, {})
      }
    }),
    local.ssh_config.public_key != "" ? yamlencode({
      machine = {
        files = [
          {
            content     = local.ssh_config.public_key
            path        = "/var/home/root/.ssh/authorized_keys"
            permissions = 384 # 0600 in octal = 384 in decimal
            op          = "create"
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

  # BIOS Configuration for modern VMs
  bios = "ovmf" # Use UEFI instead of legacy BIOS

  # EFI disk for UEFI boot
  efi_disk {
    datastore_id = local.vm_defaults.disk.datastore_id
    file_format  = "raw"
    type         = "4m"
  }

  # Boot from disk first, then CD-ROM
  # Note: CD-ROM will be ejected by deployment script after installation
  boot_order = ["virtio0", "ide2"]

  # Add Talos ISO to CD-ROM
  cdrom {
    file_id   = local.proxmox_config.iso_file_id
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
    mac_address = length(local.defaults.network.mac_addresses.control_plane) > each.value.index ? local.defaults.network.mac_addresses.control_plane[each.value.index] : each.value.mac_address
  }

  disk {
    datastore_id = local.vm_defaults.disk.datastore_id
    interface    = local.vm_defaults.disk.interface
    size         = parseint(regex("(\\d+)", local.get_vm_config[each.key].disk_size)[0], 10)
    file_format  = local.vm_defaults.disk.format
  }

  # Additional disk for etcd data
  disk {
    datastore_id = local.proxmox_config.storage.secondary
    file_format  = "raw"
    interface    = "virtio1"
    size         = local.get_vm_config[each.key].etcd_disk_gb
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
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

  # BIOS Configuration for modern VMs
  bios = "ovmf" # Use UEFI instead of legacy BIOS

  # EFI disk for UEFI boot
  efi_disk {
    datastore_id = local.vm_defaults.disk.datastore_id
    file_format  = "raw"
    type         = "4m"
  }

  # Boot from disk first, then CD-ROM (after installation)
  boot_order = ["virtio0", "ide2"]

  # Add Talos ISO to CD-ROM
  cdrom {
    file_id   = local.proxmox_config.iso_file_id
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
    mac_address = length(local.defaults.network.mac_addresses.worker) > each.value.index ? local.defaults.network.mac_addresses.worker[each.value.index] : each.value.mac_address
  }

  disk {
    datastore_id = local.vm_defaults.disk.datastore_id
    interface    = local.vm_defaults.disk.interface
    size         = parseint(regex("(\\d+)", local.get_vm_config[each.key].disk_size)[0], 10)
    file_format  = local.vm_defaults.disk.format
  }

  # Additional disk for container storage (only for storage nodes)
  dynamic "disk" {
    for_each = local.get_vm_config[each.key].storage_disk_gb != null && local.get_vm_config[each.key].storage_disk_gb > 0 ? [1] : []
    content {
      datastore_id = local.proxmox_config.storage.secondary
      file_format  = "raw"
      interface    = "virtio1"
      size         = local.get_vm_config[each.key].storage_disk_gb
    }
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
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

# =============================================================================
# CLEANUP ON DESTROY
# =============================================================================

# Clean up talos-config directory on destroy
resource "null_resource" "cleanup_talos_config" {
  triggers = {
    config_dir = "${path.module}/talos-config"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -rf ${self.triggers.config_dir}"
  }

  depends_on = [
    local_file.talosconfig,
    local_file.control_plane_configs,
    local_file.worker_configs
  ]
}
