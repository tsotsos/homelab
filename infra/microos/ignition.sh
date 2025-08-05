#!/bin/bash
if [ ! -f "ignition.tpl" ]; then
  echo "Error: ignition.tpl file not found!"
  exit 1
fi
ip_list=(10.0.1.21/24 10.0.1.22/24 10.0.1.23/24)
hostname_list=(rancher-01 rancher-02 rancher-03)


for (( i=0; i<${#ip_list[@]}; i++ )); do
    ip_address="${ip_list[i]}"
    hostname="${hostname_list[i]}"
    host_ip="10.0.1.1"
    dns_server="10.0.1.1"
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
    cp -rf micro_os_ignition.iso /var/lib/vz/template/iso/micro_os_ignition_$hostname.iso
    echo "Ignition ISO created and copied to Proxmox template directory."
    rm -rf ./iso
    rm -rf micro_os_ignition.iso
done