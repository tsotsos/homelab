terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "3.0.1-rc3"
    }
  }
  cloud {
    organization = "kng"
    workspaces {
      name = "k3s-cluster"
    }
  }
}
provider "proxmox" {
  pm_api_url          = var.proxmox_url
  pm_api_token_id     = var.proxmox_token
  pm_api_token_secret = var.proxmox_secret
  pm_tls_insecure     = var.proxmox_insecure
  pm_debug            = false
  pm_parallel         = 8
}
resource "proxmox_vm_qemu" "k3s" {
  for_each    = var.k3s_virtual_machines
  name        = each.key
  desc        = each.value.desc
  target_node = each.value.target_node
  clone       = each.value.template
  vmid        = each.value.vmid
  agent       = 1
  cores       = each.value.cores
  sockets     = each.value.sockets
  cpu         = "host"
  memory      = each.value.memory
  scsihw      = "virtio-scsi-pci"
  bootdisk    = "scsi0"
  disks {
    ide {
      ide2 {
        cdrom {
          iso = each.value.ignition
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size    = each.value.size
          storage = each.value.storage
        }
      }
      scsi1 {
        disk {
          size    = 256
          storage = "zfs-pool"
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
      disks,
    ]
  }
  tags                    = each.value.tags
  onboot                  = true
}