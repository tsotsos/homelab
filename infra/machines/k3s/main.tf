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
      name = "homelab"
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

resource "proxmox_vm_qemu" "k3s" {
  for_each    = var.k3s_virtual_machines
  name        = each.key
  desc        = each.value.desc
  target_node = each.value.target_node
  clone       = each.value.template
  vmid        = each.value.vmid
  agent       = 1
  os_type     = "cloud-init"
  cores       = each.value.cores
  sockets     = each.value.sockets
  cpu         = "host"
  memory      = each.value.memory
  scsihw      = "virtio-scsi-pci"
  bootdisk    = "scsi0"
  disks {
    scsi {
      scsi0 {
        disk {
          size    = each.value.size
          storage = each.value.storage
        }
      }
    }
  }

  network {
    model  = "virtio"
    bridge = "vmbr1"
  }
  lifecycle {
    ignore_changes = [
      network,
      disk,
    ]
  }
  cloudinit_cdrom_storage = "local-lvm"
  ciuser                  = var.k3s_user
  cipassword              = var.k3s_password
  ipconfig0               = "ip=${each.value.ip}/24,gw=${var.k3s_network_gw}"
  sshkeys                 = var.k3s_ssh_key
  tags                    = each.value.tags
  onboot                  = true
}
