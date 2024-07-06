terraform {
  required_providers {
    proxmox = {
      source  = "TheGameProfi/proxmox"
      version = "2.10.0"
    }
  }
  cloud {
    organization = "kng"

    workspaces {
      name = "dns-cluster"
    }
  }
}
provider "proxmox" {
  pm_api_url          = var.proxmox_url
  pm_api_token_id     = var.proxmox_token
  pm_api_token_secret = var.proxmox_secret
  pm_tls_insecure     = var.proxmox_insecure
  pm_debug            = false
  pm_parallel         = 3
}
resource "proxmox_lxc" "dns" {
    for_each = var.dns_containers
    vmid         = each.value.vmid
    target_node  = each.value.target_node
    hostname     = each.key
    ostemplate   = each.value.template
    memory       = each.value.memory
    cores        = each.value.cores
    tags         = each.value.tags
    cpulimit     = 0
    cpuunits     = 100
    swap         = 512
    onboot       = true
    start        = true
    unprivileged = true
    ostype       = "debian"
    pool         = "Management"
    ssh_public_keys = var.dns_ssh_key
    password     = var.dns_server_password
    rootfs {
        storage = each.value.storage
        size    = each.value.size
    }
    features {
      nesting = true
    }
    network {
      name   = "eth0"
      bridge = "vmbr0"
      firewall = true
      ip     = each.value.cidr
      gw     = var.dns_network_gw
    }
    provisioner "remote-exec" {
      inline = [
        "apt-get update",
        "apt-get upgrade -y",
        "apt-get install sudo -y",
        "adduser --disabled-password --gecos \"\" pihole",
        "echo pihole:pihole | chpasswd",
        "usermod -aG sudo pihole",
        "echo 'pihole ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers",
        "mkdir -p /home/pihole/.ssh",
        "sudo cp /root/.ssh/authorized_keys /home/pihole/.ssh",
        "sudo chown pihole:pihole /home/pihole/.ssh/authorized_keys",
        "sudo chmod 600 /home/pihole/.ssh/authorized_keys"
      ]
      connection {
        type        = "ssh"
        user        = var.dns_user
        host        = each.value.ip
        private_key = file(var.dns_private_key_path)
      }
    }
}
