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

timedatectl set-timezone Europe/Athens

if [ "${1-}" = "--prepare" ]; then
  exit 0
fi

# Redirect output to the console
exec > >(exec tee -a /dev/tty0) 2>&1
systemd-firstboot --force --keymap=us-intl # Keyboard layout
zypper --non-interactive install python3
zypper --non-interactive install nfs-client
zypper --non-interactive install open-iscsi
# Leave a marker
echo "Configured with combustion" > /etc/issue.d/combustion
# Close outputs and wait for tee to finish.
exec 1>&- 2>&-; wait;