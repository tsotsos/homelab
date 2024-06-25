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
  pm_parallel         = 6
}

locals {
  rke_virtual_machines={
    "rke-master-01" = { target_node = "s01", vmid = 201, ignition = "cephfs:iso/micro_os_ingition_rke-master-01.iso", ip = "10.0.10.21", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 64, template = "OpenSuSE-microOs", tags = "core,master", desc = "OpenSuSE microOs VM"},
    "rke-master-02" = { target_node = "s02", vmid = 202, ignition = "cephfs:iso/micro_os_ingition_rke-master-02.iso", ip = "10.0.10.22", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 64, template = "OpenSuSE-microOs", tags = "core,master", desc = "OpenSuSE microOs VM"},
    "rke-master-03" = { target_node = "s03", vmid = 203, ignition = "cephfs:iso/micro_os_ingition_rke-master-03.iso", ip = "10.0.10.23", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 64, template = "OpenSuSE-microOs", tags = "core,master", desc = "OpenSuSE microOs VM"},
    "rke-worker-01" = { target_node = "s01", vmid = 204, ignition = "cephfs:iso/micro_os_ingition_rke-worker-01.iso", ip = "10.0.10.24", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 64, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "rke-worker-02" = { target_node = "s01", vmid = 205, ignition = "cephfs:iso/micro_os_ingition_rke-worker-02.iso", ip = "10.0.10.25", sockets = 1, cores = 2, memory = 8192, storage = "local-lvm", size = 64, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "rke-worker-03" = { target_node = "s02", vmid = 206, ignition = "cephfs:iso/micro_os_ingition_rke-worker-03.iso", ip = "10.0.10.26", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 64, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "rke-worker-04" = { target_node = "s02", vmid = 207, ignition = "cephfs:iso/micro_os_ingition_rke-worker-04.iso", ip = "10.0.10.27", sockets = 1, cores = 2, memory = 8192, storage = "local-lvm", size = 64, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "rke-worker-05" = { target_node = "s03", vmid = 208, ignition = "cephfs:iso/micro_os_ingition_rke-worker-05.iso", ip = "10.0.10.28", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 64, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "rke-worker-06" = { target_node = "s03", vmid = 209, ignition = "cephfs:iso/micro_os_ingition_rke-worker-06.iso", ip = "10.0.10.29", sockets = 1, cores = 2, memory = 8192, storage = "local-lvm", size = 64, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
  }
}

resource "proxmox_vm_qemu" "rke" {
  for_each    = local.rke_virtual_machines
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