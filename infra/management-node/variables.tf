variable "proxmox_token" {
  type        = string
  description = "Proxmox token for API, use secret or ENV"
  default     = null
}
variable "proxmox_secret" {
  type        = string
  description = "Proxmox secret for API, use secret or ENV"
  default     = null
}
variable "proxmox_node" {
  type        = string
  description = "Proxmox Hostname"
  default     = null
}
variable "proxmox_url" {
  type        = string
  description = "Proxmox API"
  default     = null
}
variable "proxmox_insecure" {
  description = "Proxmox TLS Insecure"
  type        = bool
  default     = true
}
variable "k3s_network_gw" {
  type    = string
  default = null
}
variable "rancher_vms" {
  type    = map(any)
  default = {}
}
variable "k3s_ssh_key" {
  type    = string
  default = null
}
variable "k3s_user" {
  type    = string
  default = null
}
variable "k3s_password" {
  type    = string
  default = null
}
variable "k3s_workspace" {
  type    = string
  default = null
}