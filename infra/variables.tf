# =============================================================================
# TERRAFORM VARIABLES - ESSENTIAL ONLY
# =============================================================================
# 
# This file contains only variables required for Terraform operation that
# cannot be moved to cluster-config.yaml (primarily Proxmox credentials).
# 
# All cluster configuration has been moved to cluster-config.yaml:
# - Cluster settings, network config, node definitions
# - VM specifications, versions, SSH keys  
# - Storage configuration, deployment settings
#
# =============================================================================

# =============================================================================
# PROXMOX PROVIDER VARIABLES
# =============================================================================
# These are required for Terraform Proxmox provider authentication

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
# CONFIGURATION NOTE
# =============================================================================
#
# All other variables have been consolidated into cluster-config.yaml
# for unified configuration management. This establishes YAML as the 
# single source of truth for cluster configuration.
#
# To add or modify cluster settings, edit cluster-config.yaml instead
# of adding variables to this file.
#
# =============================================================================