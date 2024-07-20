#!/bin/bash
if [ ! -f "ignition.tpl" ]; then
  echo "Error: ignition.tpl file not found!"
  exit 1
fi
ip_list=(10.0.2.21/24 10.0.2.22/24 10.0.2.23/24 10.0.2.24/24 10.0.2.25/24 10.0.2.26/24 10.0.2.27/24 10.0.2.28/24 10.0.2.29/24 10.0.2.30/24 10.0.2.31/24 10.0.2.32/24 10.0.2.33/24 10.0.2.34/24)
hostname_list=(k3s-master-01 k3s-master-02 k3s-master-03 k3s-worker-01 k3s-worker-02 k3s-worker-03 k3s-worker-04 k3s-worker-05 k3s-worker-06 k3s-worker-07 k3s-worker-08 k3s-worker-09 k3s-worker-10 k3s-worker-11)


for (( i=0; i<${#ip_list[@]}; i++ )); do
    ip_address="${ip_list[i]}"
    hostname="${hostname_list[i]}"
    host_ip="10.0.2.1"
    dns_server="10.0.1.7"
    rm -rf ./iso
    mkdir -p iso/ignition
    mkdir -p iso/combustion
    # combustion
    combustion_content=$(cat combustion.sh)
    modified_combustion_content=$(echo "$combustion_content" | awk '{ gsub(/VM_IP/, "'"$ip_address"'"); gsub(/HOST/, "'"$host_ip"'"); gsub(/DNS_SERVER/, "'"$dns_server"'"); print}')
    echo "$modified_combustion_content" > iso/combustion/script
    echo "Successfully copied the contents of combustion script"
    # ignition
    ingition_content=$(cat ignition.tpl)
    modified_ignition_content=$(echo "$ingition_content" | awk '{ gsub(/HOST/, "'"$hostname"'"); print }')
    echo "$modified_ignition_content" > iso/ignition/config.ign
    echo "Successfully copied the contents of combustion script"
    # create ignition iso
    mkisofs -o micro_os_ignition.iso -V ignition iso
    mkisofs -full-iso9660-filenames -o micro_os_ignition.iso -V ignition iso
    cp -rf micro_os_ignition.iso /mnt/pve/nfs-ds/template/iso/micro_os_ignition_$hostname.iso
    echo "Ignition ISO created and copied to Proxmox template directory."
    rm -rf ./iso
    rm -rf micro_os_ignition.iso
done