packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.6"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

locals {
  ssh_port = "2222"
  boot_command = [
    "<wait45s>root<enter><wait>",
    "ifconfig 'eth0' up && udhcpc -i 'eth0'<enter><wait5s>",
    "setup-alpine -q<enter><wait>",
    # Select US keyboard layout.
    "us<enter>",
    "us<enter><wait10s>",
    "setup-timezone -z Israel<enter><wait>",
    "setup-sshd -c openssh<enter><wait>",
    "setup-disk -m sys /dev/sda<enter>",
    "y<enter><wait30s>",
    # Mount installation partition and change configuration.
    "mount /dev/sda3 /mnt<enter>",
    # Enable root login for Packer.
    "echo 'PermitRootLogin yes' >> /mnt/etc/ssh/sshd_config<enter>",
    "echo 'Port ${local.ssh_port}' >> /mnt/etc/ssh/sshd_config<enter>",
    # Ensure virtio and storage features are in initramfs for next reboot.
    "sed -i 's/features=\"/features=\"virtio scsi cdrom ata /' /mnt/etc/mkinitfs/mkinitfs.conf<enter>",
    # Rebuild initramfs for the installed system.
    "chroot /mnt mkinitfs<enter><wait15s>",
    # Reboot and setup QEMU Guest Agent so Packer can connect with SSH.
    "reboot<enter><wait30s>",
    "root<enter><wait>",
    # Set root password.
    "echo 'root:${var.ssh_password}' | chpasswd<enter>",
    # Enable community repository.
    "sed -i 's:#\\(.*/v.*/community\\):\\1:' /etc/apk/repositories<enter>",
    "apk update<enter><wait5s>",
    "apk add qemu-guest-agent<enter><wait5s>",
    # Add and start OpenRC service.
    "rc-update add qemu-guest-agent<enter>",
    "rc-service qemu-guest-agent start<enter><wait5s>",
  ]
}

source "proxmox-iso" "pve1" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true

  node  = "pve1"
  vm_id = var.node_vm_ids["pve1"]

  boot_iso {
    type             = "ide"
    iso_url          = var.iso_url
    iso_checksum     = var.iso_checksum
    iso_storage_pool = var.proxmox_iso_pool
    unmount          = true
  }

  template_name        = "${var.template_name}${var.template_name_suffix}"
  template_description = var.template_description

  scsi_controller = "virtio-scsi-single"
  os              = "l26"
  qemu_agent      = true

  cores  = var.cores
  memory = var.memory

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disks {
    type         = "scsi"
    disk_size    = var.disk_size
    storage_pool = var.proxmox_storage_pool
    format       = "raw"
    io_thread    = true
  }

  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_port     = local.ssh_port
  ssh_timeout  = "15m"

  boot_command = local.boot_command

  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage_pool
}

source "proxmox-iso" "pve2" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true

  node  = "pve2"
  vm_id = var.node_vm_ids["pve2"]

  boot_iso {
    type             = "ide"
    iso_url          = var.iso_url
    iso_checksum     = var.iso_checksum
    iso_storage_pool = var.proxmox_iso_pool
    unmount          = true
  }

  template_name        = "${var.template_name}${var.template_name_suffix}"
  template_description = var.template_description

  scsi_controller = "virtio-scsi-single"
  os              = "l26"
  qemu_agent      = true

  cores  = var.cores
  memory = var.memory

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disks {
    type         = "scsi"
    disk_size    = var.disk_size
    storage_pool = var.proxmox_storage_pool
    format       = "raw"
    io_thread    = true
  }

  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_port     = local.ssh_port
  ssh_timeout  = "15m"

  boot_command = local.boot_command

  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage_pool
}

source "proxmox-iso" "pve3" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true

  node  = "pve3"
  vm_id = var.node_vm_ids["pve3"]

  boot_iso {
    type             = "ide"
    iso_url          = var.iso_url
    iso_checksum     = var.iso_checksum
    iso_storage_pool = var.proxmox_iso_pool
    unmount          = true
  }

  template_name        = "${var.template_name}${var.template_name_suffix}"
  template_description = var.template_description

  scsi_controller = "virtio-scsi-single"
  os              = "l26"
  qemu_agent      = true

  cores  = var.cores
  memory = var.memory

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disks {
    type         = "scsi"
    disk_size    = var.disk_size
    storage_pool = var.proxmox_storage_pool
    format       = "raw"
    io_thread    = true
  }

  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_port     = local.ssh_port
  ssh_timeout  = "15m"

  boot_command = local.boot_command

  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage_pool
}

build {
  sources = [
    "source.proxmox-iso.pve1",
    "source.proxmox-iso.pve2",
    "source.proxmox-iso.pve3"
  ]

  # Main setup script.
  provisioner "shell" {
    script = "scripts/setup.sh"
  }
}
