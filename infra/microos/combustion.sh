#!/bin/bash
# combustion: network
umask 077 # Required for NM config
mkdir -p /etc/NetworkManager/system-connections/
cat >/etc/NetworkManager/system-connections/ens18.nmconnection <<-EOF

[connection]
id=ens18
type=ethernet
interface-name=ens18

[ipv4]
dns-search=
method=manual
address1=VM_IP,HOST
dns=DNS_SERVER

[ipv6]
dns-search=
addr-gen-mode=eui64
method=auto
EOF
# combustion: prepare
if [ "${1-}" = "--prepare" ]; then
  exit 0
fi
# Redirect output to the console
exec > >(exec tee -a /dev/tty0) 2>&1
systemd-firstboot --force --keymap=us-intl # Keyboard layout
zypper --non-interactive install python3
zypper --non-interactive install nfs-client
zypper --non-interactive install open-iscsi
# Mount disk
echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/sdb
mkfs.btrfs /dev/sdb1
mkdir -p /var/lib/longhorn
chmod 775 /var/lib/longhorn
mount -o noatime /dev/sdb1 /var/lib/longhorn
UUID=$(blkid -s UUID -o value /dev/sdb1)
echo "UUID=$UUID  /var/lib/longhorn   btrfs   defaults,noatime   0   0" >> /etc/fstab

# Leave a marker
echo "Configured with combustion" > /etc/issue.d/combustion
# Close outputs and wait for tee to finish.
exec 1>&- 2>&-; wait;