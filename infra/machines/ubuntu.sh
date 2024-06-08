#!/bin/bash

# VM ID variable (easily change this if needed)
VM_ID=11000
VM_NAME="ubuntu-cloud"

# Storage and Network Variables
STORAGE="local-lvm"   # Adjust if you use different storage
BRIDGE="vmbr1"         # Replace with your actual bridge interface

# Ubuntu cloud image URL
UBUNTU_IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMAGE_FILE="jammy-server-cloudimg-amd64.img"

# Check if image exists, download if not
if [ ! -f "$IMAGE_FILE" ]; then
  echo "Downloading Ubuntu cloud image..."
  wget "$UBUNTU_IMAGE_URL"
else
  echo "Ubuntu cloud image already exists. Skipping download."
fi

# Customize the image
virt-customize -a $IMAGE_FILE --install qemu-guest-agent
virt-customize -a $IMAGE_FILE --run-command 'apt remove snapd -y'
virt-customize -a $IMAGE_FILE --run-command 'snap list | while read snap; do snap remove "$snap"; done'
virt-customize -a $IMAGE_FILE --run-command 'systemctl enable qemu-guest-agent.service'
virt-customize -a $IMAGE_FILE --update

# Create the VM
qm create $VM_ID --memory 2048 --cores 2 --name $VM_NAME --net0 virtio,bridge=$BRIDGE

# Import the disk image
qm importdisk $VM_ID $IMAGE_FILE $STORAGE

# Set the disk as SCSI
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 ${STORAGE}:vm-${VM_ID}-disk-0

# Enable QEMU Guest Agent
qm set $VM_ID  --agent enabled=1

# Set boot order and options
qm set $VM_ID --boot c --bootdisk scsi0

# Configure serial console (optional)
qm set $VM_ID --serial0 socket --vga serial0

# Create the template
qm template $VM_ID