#!/bin/bash
# VM ID variable (easily change this if needed)
VM_ID=10000
VM_NAME="OpenSuSE-microOs"
STORAGE="local-lvm"   # Adjust if you use different storage
BRIDGE="vmbr1"         # Replace with your actual bridge interface
# Suse MicroOS image
MICRO_OS="https://download.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-16.0.0-ContainerHost-kvm-and-xen-Snapshot20240629.qcow2"
IMAGE_FILE="openSUSE-MicroOS.x86_64-16.0.0-ContainerHost-kvm-and-xen-Snapshot20240629.qcow2"

# Check if image exists, download if not
if [ ! -f "$IMAGE_FILE" ]; then
  echo "Downloading Ubuntu cloud image..."
  wget "$MICRO_OS"
else
  echo "Image already exists. Skipping download."
fi
qm create $VM_ID --memory 2048 --cores 2 --name $VM_NAME --net0 virtio,bridge=$BRIDGE
qm importdisk $VM_ID $IMAGE_FILE $STORAGE
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 ${STORAGE}:vm-${VM_ID}-disk-0
qm set $VM_ID --vga qxl
qm set $VM_ID --agent 1
qm set $VM_ID --ide2 none,media=cdrom
qm set $VM_ID --boot order=scsi0
qm set $VM_ID --name $VM_NAME
qm template $VM_ID