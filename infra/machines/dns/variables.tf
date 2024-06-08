variable "proxmox_token" {
  description = "Proxmox token for API, use secret or ENV"
  type        = string
}
variable "proxmox_secret" {
  description = "Proxmox secret for API, use secret or ENV"
  type        = string
}
variable "proxmox_node" {
  description = "Proxmox Hostname"
  default = null
}
variable "proxmox_url" {
  description = "Proxmox API"
  default = null
}
variable "proxmox_insecure" {
  description = "Proxmox TLS Insecure"
  default = true
}
variable "dns_network_gw" {
  type    = string
  default = null
}
variable "dns_containers" {
  type    = map(any)
  default = {}
}
variable "dns_ssh_key" {
  type    = string
  default = null
}
variable "dns_private_key_path" {
  type    = string
  default = null
}
variable "dns_user" {
  type    = string
  default = null
}
variable "dns_server_password" {
  type    = string
  default = null
}
variable "dns_workspace" {
  type    = string
  default = null  
}