#!/bin/sh
set -e

echo "Updating package index..."
apk update

echo "Installing essential packages..."
# Installing HAProxy, Keepalived, QEMU Guest Agent, Cloud-init, and dependencies
# e2fsprogs-extra is required by Cloud Init for creating/resizing filesystems.
apk add \
    haproxy \
    keepalived \
    qemu-guest-agent \
    cloud-init \
    alpine-conf \
    cloud-utils-growpart \
    e2fsprogs-extra \
    util-linux \
    blkid \
    lsblk \
    pciutils \
    shadow \
    sudo \
    curl \
    vim \
    bash \
    net-tools \
    python3

echo "Configuring kernel modules and initramfs..."
# Ensure essential modules are loaded at boot to detect storage and CD-ROM
for mod in virtio_scsi virtio_pci virtio_blk sr_mod; do
    if ! grep -q "^$mod" /etc/modules; then
        echo "$mod" >> /etc/modules
    fi
done

# Ensure storage features are in mkinitfs for proper boot and device detection
# Default features usually: ata base ide scsi virtio network ext4
for feature in virtio scsi cdrom ata; do
    if ! grep -q "$feature" /etc/mkinitfs/mkinitfs.conf; then
        sed -i "s/features=\"/features=\"$feature /" /etc/mkinitfs/mkinitfs.conf
    fi
done
mkinitfs

echo "Configuring services to start at boot..."
rc-update add sshd default
# HAProxy and Keepalived will be enabled by Terraform after configuration
rc-update add qemu-guest-agent default

# Ensure users are unlocked for SSH key authentication
# Alpine's sshd refuses login if the account is locked in /etc/shadow (!)
for user in root alpine; do
    if ! id "$user" >/dev/null 2>&1; then
        adduser -D "$user"
    fi
    # Unlock account by setting a non-locking password field (*)
    sed -i "s/^$user:!:/$user:*:/; s/^$user:!!:/$user:*:/;" /etc/shadow
    passwd -u "$user" || true
done

# Ensure sshd_config is correct for key-based authentication on port 2222
cat <<EOF > /etc/ssh/sshd_config
# Optimized sshd_config for Alpine Load Balancer
Port 2222
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Logging
SyslogFacility AUTH
LogLevel INFO

# Authentication
PermitRootLogin prohibit-password
StrictModes yes
PubkeyAuthentication yes
PasswordAuthentication no
AuthorizedKeysFile .ssh/authorized_keys

# Misc
Subsystem sftp /usr/lib/ssh/sftp-server
EOF

# Using setup-cloud-init if available ensures correct runlevels (local in boot, others in default)
if command -v setup-cloud-init >/dev/null; then
    setup-cloud-init
else
    rc-update add cloud-init-local boot
    rc-update add cloud-init default
    rc-update add cloud-config default
    rc-update add cloud-final default
fi

# Ensure HAProxy and Keepalived configuration directories exist with correct permissions
mkdir -p /etc/haproxy /etc/keepalived
chown root:root /etc/haproxy /etc/keepalived
chmod 755 /etc/haproxy /etc/keepalived

# Ensure HAProxy runtime directory exists
mkdir -p /run/haproxy
chown haproxy:haproxy /run/haproxy
chmod 750 /run/haproxy

echo "Configuring cloud-init for Proxmox..."
mkdir -p /etc/cloud/cloud.cfg.d

# Explicitly set datasource list with fallback to None
cat <<EOF > /etc/cloud/cloud.cfg.d/10_datasource.cfg
datasource_list: [ NoCloud, ConfigDrive, None ]
EOF

cat <<EOF > /etc/cloud/cloud.cfg.d/99_proxmox.cfg
system_info:
  default_user:
    name: alpine
    groups: [wheel]
    lock_passwd: false
disable_root: false
EOF

# Ensure the alpine user has sudo access
echo "Configuring sudoers..."
mkdir -p /etc/sudoers.d
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# Clean up cloud-init state to ensure it runs on first boot of the instance
rm -rf /var/lib/cloud/*

echo "Cleaning up..."
rm -rf /var/cache/apk/*
rm -rf /root/.ash_history
rm -rf /home/alpine/.ash_history

echo "Packer setup completed successfully."
