# =============================================================================
# PROXMOX PROVIDER VARIABLES
# =============================================================================

variable "proxmox_ve_endpoint" {
  description = "Proxmox VE endpoint URL"
  type        = string
  validation {
    condition     = can(regex("^https?://", var.proxmox_ve_endpoint))
    error_message = "The proxmox_ve_endpoint must be a valid URL starting with http:// or https://."
  }
}
variable "proxmox_ve_username" {
  description = "Proxmox VE username for authentication (only used for password auth)"
  type        = string
  default     = ""
}

variable "proxmox_ve_password" {
  description = "Proxmox VE password for authentication (only used for password auth)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "proxmox_ve_api_token" {
  description = "Proxmox VE API token for authentication (format: 'user@realm!tokenid=secret')"
  type        = string
  default     = ""
  sensitive   = true
}

variable "proxmox_ve_insecure" {
  description = "Whether to skip TLS verification for Proxmox VE API"
  type        = bool
  default     = true
}

variable "proxmox_ve_ssh_username" {
  description = "SSH username for Proxmox VE nodes"
  type        = string
  default     = "root"
}

# =============================================================================
# CLUSTER CONFIGURATION
# =============================================================================

variable "cluster_name" {
  description = "Name of the Talos Kubernetes cluster"
  type        = string
  default     = "kng-cluster"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cluster_endpoint" {
  description = "Kubernetes API server endpoint (VIP with port)"
  type        = string
  default     = "https://10.0.2.100:6443"
  
  validation {
    condition     = can(regex("^https://[0-9.]+:[0-9]+$", var.cluster_endpoint))
    error_message = "Cluster endpoint must be a valid HTTPS URL with IP and port."
  }
}

variable "cluster_vip" {
  description = "Virtual IP address for the control plane load balancing"
  type        = string
  default     = "10.0.2.100"
  
  validation {
    condition     = can(cidrhost("${var.cluster_vip}/32", 0))
    error_message = "Cluster VIP must be a valid IP address."
  }
}

variable "cluster_cni" {
  description = "Container Network Interface plugin to use"
  type        = string
  default     = "flannel"
  
  validation {
    condition     = contains(["flannel", "cilium", "calico"], var.cluster_cni)
    error_message = "CNI must be one of: flannel, cilium, calico."
  }
}

variable "allow_scheduling_on_control_planes" {
  description = "Whether to allow scheduling workloads on control plane nodes"
  type        = bool
  default     = false
}

variable "talos_iso_file_id" {
  description = "Proxmox file ID for the Talos ISO (format: 'storage:iso/filename.iso')"
  type        = string
  default     = "local:iso/talosOS-1.11.5.iso"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+:iso/.+\\.iso$", var.talos_iso_file_id))
    error_message = "Talos ISO file ID must be in format 'storage:iso/filename.iso'."
  }
}

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================

variable "network_gateway" {
  description = "Default gateway for the VM network"
  type        = string
  default     = "10.0.2.1"
  
  validation {
    condition     = can(cidrhost("${var.network_gateway}/32", 0))
    error_message = "Network gateway must be a valid IP address."
  }
}

variable "network_cidr" {
  description = "Network CIDR prefix length"
  type        = string
  default     = "24"
  
  validation {
    condition     = can(parseint(var.network_cidr, 10)) && parseint(var.network_cidr, 10) >= 8 && parseint(var.network_cidr, 10) <= 30
    error_message = "Network CIDR must be between 8 and 30."
  }
}

variable "dns_servers" {
  description = "DNS servers for the VMs"
  type        = list(string)
  default     = ["8.8.8.8", "1.1.1.1"]
  
  validation {
    condition     = length(var.dns_servers) > 0 && alltrue([for ip in var.dns_servers : can(cidrhost("${ip}/32", 0))])
    error_message = "DNS servers must be a non-empty list of valid IP addresses."
  }
}

variable "control_plane_mac_addresses" {
  description = "List of MAC addresses for control plane nodes (for DHCP reservations)"
  type        = list(string)
  default     = []
  
  validation {
    condition = length([
      for mac in var.control_plane_mac_addresses : mac
      if can(regex("^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$", mac))
    ]) == length(var.control_plane_mac_addresses)
    error_message = "MAC addresses must be in format XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX."
  }
}

variable "worker_mac_addresses" {
  description = "List of MAC addresses for worker nodes (for DHCP reservations)"
  type        = list(string)
  default     = []
  
  validation {
    condition = length([
      for mac in var.worker_mac_addresses : mac
      if can(regex("^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$", mac))
    ]) == length(var.worker_mac_addresses)
    error_message = "MAC addresses must be in format XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX."
  }
}

# =============================================================================
# NODE CONFIGURATION
# =============================================================================

variable "control_plane_count" {
  description = "Number of control plane nodes (should be odd for HA)"
  type        = number
  default     = 3
  
  validation {
    condition     = var.control_plane_count > 0 && var.control_plane_count % 2 == 1
    error_message = "Control plane count must be a positive odd number for HA."
  }
}

variable "worker_count_per_proxmox_node" {
  description = "Number of worker nodes per Proxmox host"
  type        = number
  default     = 2
  
  validation {
    condition     = var.worker_count_per_proxmox_node >= 0
    error_message = "Worker count per Proxmox node must be non-negative."
  }
}

variable "proxmox_nodes" {
  description = "List of Proxmox node names where VMs will be deployed"
  type        = list(string)
  default     = ["pve-node-1", "pve-node-2", "pve-node-3"]
  
  validation {
    condition     = length(var.proxmox_nodes) > 0
    error_message = "At least one Proxmox node must be specified."
  }
}

# =============================================================================
# VM CONFIGURATION
# =============================================================================

variable "vm_bridge" {
  description = "Network bridge for VM network interfaces"
  type        = string
  default     = "vmbr1"
}

variable "vm_vlan_id" {
  description = "VLAN ID for VM network interfaces (null for untagged)"
  type        = number
  default     = null
}

variable "vm_storage" {
  description = "Primary storage datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "vm_storage_secondary" {
  description = "Secondary storage datastore for additional VM disks"
  type        = string
  default     = "zfs-pool"
}

variable "vm_cpu_cores" {
  description = "Number of CPU cores per VM"
  type        = number
  default     = 4
  
  validation {
    condition     = var.vm_cpu_cores > 0 && var.vm_cpu_cores <= 64
    error_message = "VM CPU cores must be between 1 and 64."
  }
}

variable "vm_memory" {
  description = "Memory allocation per VM in MB (default for all VMs)"
  type        = number
  default     = 8192
  
  validation {
    condition     = var.vm_memory >= 2048
    error_message = "VM memory must be at least 2048 MB for Kubernetes nodes."
  }
}

variable "control_plane_memory" {
  description = "Memory allocation per control plane VM in MB (overrides vm_memory if set)"
  type        = number
  default     = null
  
  validation {
    condition     = var.control_plane_memory == null || var.control_plane_memory >= 4096
    error_message = "Control plane memory must be at least 4096 MB."
  }
}

variable "worker_memory" {
  description = "Memory allocation per worker VM in MB (overrides vm_memory if set)"
  type        = number
  default     = null
  
  validation {
    condition     = var.worker_memory == null || var.worker_memory >= 2048
    error_message = "Worker memory must be at least 2048 MB."
  }
}

variable "vm_disk_size" {
  description = "Primary disk size for VMs (e.g., '30G') - default for all VMs"
  type        = string
  default     = "30G"
  
  validation {
    condition     = can(regex("^[0-9]+[GgTt]$", var.vm_disk_size))
    error_message = "VM disk size must be in format like '30G' or '1T'."
  }
}

variable "control_plane_disk_size" {
  description = "Primary disk size for control plane VMs (overrides vm_disk_size if set)"
  type        = string
  default     = null
  
  validation {
    condition     = var.control_plane_disk_size == null || can(regex("^[0-9]+[GgTt]$", var.control_plane_disk_size))
    error_message = "Control plane disk size must be in format like '30G' or '1T'."
  }
}

variable "worker_disk_size" {
  description = "Primary disk size for worker VMs (overrides vm_disk_size if set)"
  type        = string
  default     = null
  
  validation {
    condition     = var.worker_disk_size == null || can(regex("^[0-9]+[GgTt]$", var.worker_disk_size))
    error_message = "Worker disk size must be in format like '30G' or '1T'."
  }
}

variable "per_vm_config" {
  description = "Per-VM configuration overrides (memory_mb, disk_size, cpu_cores, etcd_disk_gb, storage_disk_gb)"
  type = map(object({
    memory_mb       = optional(number)
    disk_size       = optional(string)
    cpu_cores       = optional(number)
    etcd_disk_gb    = optional(number)  # For control plane nodes only
    storage_disk_gb = optional(number)  # For worker nodes only
  }))
  default = {}
  
  validation {
    condition = alltrue([
      for vm_name, config in var.per_vm_config : alltrue([
        config.memory_mb == null || config.memory_mb >= 2048,
        config.cpu_cores == null || (config.cpu_cores > 0 && config.cpu_cores <= 64),
        config.disk_size == null || can(regex("^[0-9]+[GgTt]$", config.disk_size)),
        config.etcd_disk_gb == null || config.etcd_disk_gb >= 5,
        config.storage_disk_gb == null || config.storage_disk_gb >= 20
      ])
    ])
    error_message = "Per-VM config validation failed: memory_mb >= 2048, cpu_cores 1-64, disk_size format 'XG'/'XT', etcd_disk_gb >= 5, storage_disk_gb >= 20."
  }
}

variable "control_plane_etcd_disk_size" {
  description = "Additional disk size for etcd data on control plane nodes (GB)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.control_plane_etcd_disk_size >= 5
    error_message = "Control plane etcd disk size must be at least 5 GB."
  }
}

variable "worker_storage_disk_size" {
  description = "Additional disk size for container storage on worker nodes (GB)"
  type        = number
  default     = 50
  
  validation {
    condition     = var.worker_storage_disk_size >= 20
    error_message = "Worker storage disk size must be at least 20 GB."
  }
}

variable "vm_default_username" {
  description = "Default username for VM initialization"
  type        = string
  default     = "talos"
}

variable "vm_default_password" {
  description = "Default password for VM initialization (will be ignored after Talos boot)"
  type        = string
  default     = "changeme"
  sensitive   = true
}

# =============================================================================
# SSH CONFIGURATION
# =============================================================================

variable "ssh_public_key" {
  description = "SSH public key for emergency access to Talos nodes"
  type        = string
  default     = ""
}

# =============================================================================
# TALOS CONFIGURATION
# =============================================================================

variable "talos_version" {
  description = "Talos Linux version to install"
  type        = string
  default     = "v1.8.0"
  
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.talos_version))
    error_message = "Talos version must be in format vX.Y.Z."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "v1.31.1"
  
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.kubernetes_version))
    error_message = "Kubernetes version must be in format vX.Y.Z."
  }
}

variable "talos_install_disk" {
  description = "Disk device path for Talos installation"
  type        = string
  default     = "/dev/vda"
}

# =============================================================================
# SYSTEM CONFIGURATION
# =============================================================================

variable "control_plane_sysctls" {
  description = "Kernel parameters (sysctls) for control plane nodes"
  type        = map(string)
  default = {
    "net.core.somaxconn"           = "65535"
    "net.core.netdev_max_backlog"  = "4096"
    "net.ipv4.ip_forward"          = "1"
    "net.bridge.bridge-nf-call-iptables" = "1"
  }
}

variable "worker_sysctls" {
  description = "Kernel parameters (sysctls) for worker nodes"
  type        = map(string)
  default = {
    "net.core.somaxconn"           = "65535"
    "net.core.netdev_max_backlog"  = "4096"
    "net.ipv4.ip_forward"          = "1"
    "net.bridge.bridge-nf-call-iptables" = "1"
  }
}

variable "control_plane_kubelet_extra_args" {
  description = "Additional kubelet arguments for control plane nodes"
  type        = map(string)
  default = {
    "rotate-server-certificates" = "true"
    "protect-kernel-defaults"    = "true"
  }
}

variable "worker_kubelet_extra_args" {
  description = "Additional kubelet arguments for worker nodes"
  type        = map(string)
  default = {
    "rotate-server-certificates" = "true"
    "protect-kernel-defaults"    = "true"
  }
}
