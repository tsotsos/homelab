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

locals {
  k3s_virtual_machines={
    "k3s-master-01" = { target_node = "s01", vmid = 201, ignition = "nfs-ds:iso/micro_os_ignition_k3s-master-01.iso", ip = "10.0.2.21", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,master", desc = "OpenSuSE microOs VM"},
    "k3s-master-02" = { target_node = "s02", vmid = 202, ignition = "nfs-ds:iso/micro_os_ignition_k3s-master-02.iso", ip = "10.0.2.22", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,master", desc = "OpenSuSE microOs VM"},
    "k3s-master-03" = { target_node = "s03", vmid = 203, ignition = "nfs-ds:iso/micro_os_ignition_k3s-master-03.iso", ip = "10.0.2.23", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,master", desc = "OpenSuSE microOs VM"},
    "k3s-master-04" = { target_node = "s02", vmid = 204, ignition = "nfs-ds:iso/micro_os_ignition_k3s-master-04.iso", ip = "10.0.2.24", sockets = 1, cores = 2, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,master", desc = "OpenSuSE microOs VM"},
    "k3s-master-05" = { target_node = "s03", vmid = 205, ignition = "nfs-ds:iso/micro_os_ignition_k3s-master-05.iso", ip = "10.0.2.25", sockets = 1, cores = 2, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,master", desc = "OpenSuSE microOs VM"},    
    "k3s-worker-01" = { target_node = "s01", vmid = 206, ignition = "nfs-ds:iso/micro_os_ignition_k3s-worker-01.iso", ip = "10.0.2.26", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "k3s-worker-02" = { target_node = "s01", vmid = 207, ignition = "nfs-ds:iso/micro_os_ignition_k3s-worker-02.iso", ip = "10.0.2.27", sockets = 1, cores = 2, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "k3s-worker-03" = { target_node = "s02", vmid = 208, ignition = "nfs-ds:iso/micro_os_ignition_k3s-worker-03.iso", ip = "10.0.2.28", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "k3s-worker-04" = { target_node = "s02", vmid = 209, ignition = "nfs-ds:iso/micro_os_ignition_k3s-worker-04.iso", ip = "10.0.2.29", sockets = 1, cores = 2, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "k3s-worker-05" = { target_node = "s03", vmid = 210, ignition = "nfs-ds:iso/micro_os_ignition_k3s-worker-05.iso", ip = "10.0.2.30", sockets = 1, cores = 4, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "k3s-worker-06" = { target_node = "s03", vmid = 211, ignition = "nfs-ds:iso/micro_os_ignition_k3s-worker-06.iso", ip = "10.0.2.31", sockets = 1, cores = 2, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "k3s-worker-07" = { target_node = "s03", vmid = 212, ignition = "nfs-ds:iso/micro_os_ignition_k3s-worker-07.iso", ip = "10.0.2.32", sockets = 1, cores = 2, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "k3s-worker-08" = { target_node = "s03", vmid = 213, ignition = "nfs-ds:iso/micro_os_ignition_k3s-worker-08.iso", ip = "10.0.2.33", sockets = 1, cores = 2, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
    "k3s-worker-09" = { target_node = "s03", vmid = 214, ignition = "nfs-ds:iso/micro_os_ignition_k3s-worker-09.iso", ip = "10.0.2.34", sockets = 1, cores = 2, memory = 8192, storage = "local-lvm", size = 94, template = "OpenSuSE-microOs", tags = "core,worker", desc = "OpenSuSE microOs VM"},
  }
}

resource "proxmox_vm_qemu" "k3s" {
  for_each    = local.k3s_virtual_machines
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