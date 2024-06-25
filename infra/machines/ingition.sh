#!/bin/bash
if [ ! -f "ignition.tpl" ]; then
  echo "Error: ignition.tpl file not found!"
  exit 1
fi
ip_list=(10.0.10.21/24 10.0.10.22/24 10.0.10.23/24 10.0.10.24/24 10.0.10.25/24 10.0.10.26/24 10.0.10.27/24 10.0.10.27/24 10.0.10.28/24 10.0.10.29/24)
hostname_list=(rke-master-01 rke-master-02 rke-master-03 rke-worker-01 rke-worker-02 rke-worker-03 rke-worker-04 rke-worker-05 rke-worker-06)

for (( i=0; i<${#ip_list[@]}; i++ )); do
    ip_address="${ip_list[i]}"
    hostname="${hostname_list[i]}"
    rm -rf ./iso
    mkdir -p iso/ignition
    ignition_content=$(cat ignition.tpl)
    modified_content=$(echo "$ignition_content" | awk '{ gsub(/VM_IP/, "'"$ip_address"'"); gsub(/HOST/, "'"$hostname"'"); print }')
    echo "$modified_content" > iso/ignition/config.ign
    echo "Successfully copied the contents of ignition.tpl"
    mkisofs -o micro_os_ingition.iso -V ignition iso
    cp -rf micro_os_ingition.iso /var/lib/vz/template/iso/micro_os_ingition_$hostname.iso
    echo "Ignition ISO created and copied to Proxmox template directory."
    rm -rf ./iso
    rm -rf micro_os_ignition.iso
done