#version=RHEL10
# Kickstart for pico-3 — minimum config only.
# Scope: disk layout + whatever is needed for Ansible to get SSH + sudo access.
# Everything else (chrony, firewalld, NetworkManager, subscription, iscsi/nfs
# packages, RKE2 itself) is Ansible's job — see PLAN.md "Host Prep (RHEL)".

text
lang en_US.UTF-8
keyboard --xlayouts='us'

# Disk — wipe and let Anaconda lay out LVM + /boot/efi for Gen2 UEFI
zerombr
clearpart --all --initlabel
autopart --type=lvm --fstype=xfs
bootloader --timeout=1

# Network — DHCP, per-environment NIC name (eth0 sandbox, verify on lab hardware).
# The node's fixed address comes from a UniFi DHCP reservation keyed to its
# static MAC, outside the normal DHCP pool — not a static config here.
network --device=eth0 --bootproto=dhcp --hostname=pico-3.taco.moe --activate --onboot=yes

timezone UTC --utc

# SELinux enforcing from first boot — avoids a relabel-and-reboot cycle later
selinux --enforcing

# Root login fully locked. No password, no SSH. The bootstrap user below is
# the only way in.
rootpw --lock

# Bootstrap user — SSH-key login only (locked password), wheel for sudo
user --name=ryan --groups=wheel --lock
sshkey --username=ryan "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC1uFSEio4vE367ne7R29g9InH4sqKTgvByJqbegQ2ZSzE7TiijH4pC3N8Zz6tR4DNPU7zRdNkcPwMpNByaqFQbu22YsYQYe01G2uQvMpc/PzroWlN0F/Xh7b69Fv1Thk/FlCFE2iMZ0yjSu7wxthrcCdj4w/SWB3/SC0fODoMEWy7Df7mjCXhGdMVfhHN1S+fPuBgo2UWFNmAmDrT1nct39bA71B+s9VrVj23Q076FiLthhj7rqtMJU9uGM04QHquK+syMMHlf0clSassw+snNEw5V2jI3f5/xRhLQEIfACRYUZTkRNFdXLCohHz1/iD0IY7OyK0q9uW+c62mZZV9/CIcGYVE2T9xlSIkYYfJ65pJWAQwNIU11bd6kwXVhIacM8rnJFt/meMdgnUDNCYDPDoiOKryVkIRsTbs150xhncUUHJoNekqV8yWjV8U6+2F1+P538ndZ63VXW6M12gu+LjDhF9qnoOPGeSc1t+oG8ilWR/RSOHfaJ8v2bwPmoOzcERD9dKsTr/U+UzULK+sEg/PMlH2aWQgNm3Bw6UOb3YQ5CW+7b61pzVmEANecufEg2YgVSp/HkAG0t7iCIX4ZeciOH23aC+AffBRKal+PTUGU2vX7v5nhHV2zGIHKO04E58NPdAaK+mkQF/HNbalqI7UJ3IxMfVTXCpFlQMsaTQ== ryan@taco.moe"

%packages
@^minimal-environment
python3
openssh-server
%end

# Passwordless sudo for the bootstrap user, so Ansible's `become` doesn't need
# an interactive password.
%post
echo "ryan ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ryan
chmod 440 /etc/sudoers.d/ryan
%end

reboot
