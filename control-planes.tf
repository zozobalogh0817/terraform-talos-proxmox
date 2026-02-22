resource "proxmox_vm_qemu" "control_plane" {
  target_node  = "pve1"
  description  = "Control Plane Test from Terraform"
  vmid         = 401
  name         = "control-plane"

  memory  = 8192
  balloon = 0 # ballooning disabled (recommended in your screenshot)

  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
  }

  # OS disk
  disk {
    slot     = "scsi0"
    type     = "disk"
    storage  = "local-lvm"
    size     = "100G"
    iothread = true

    # Optional but aligns with screenshot guidance
    format = "raw"
    cache  = "writethrough"
  }

  # You said QEMU agent is solved and Proxmox now shows DHCP IPs
  agent  = 1

  # Helps prevent long waits if you don't have IPv6
  skip_ipv6 = true

  # Recommended firmware/platform
  bios    = "ovmf"  # UEFI
  machine = "q35"   # PCIe-based machine type

  network {
    id     = 0
    bridge = "vmbr0"
    model  = "virtio"
  }

  # Disk controller: VirtIO SCSI (NOT virtio-scsi-single)
  scsihw = "virtio-scsi-pci"

  # Talos ISO as CD-ROM
  disk {
    slot    = "ide2"
    type    = "cdrom"
    iso     = "local:iso/talos-qemu-agent-metal-amd64.iso"
  }

  # EFI disk required for OVMF (UEFI)
  efidisk {
    efitype = "4m"
    storage = "local-lvm"

    # NOTE: keep this false unless you know your image supports Secure Boot
    pre_enrolled_keys = false
  }

  # Optional: VirtIO RNG device (better entropy)
  rng {
    source = "/dev/urandom"
  }

  boot     = "order=ide2;scsi0"
  bootdisk = "scsi0"
}

output "control_plane_ipv4" {
  value       = proxmox_vm_qemu.control_plane.default_ipv4_address
  description = "DHCP IPv4 address reported by Proxmox provider (usually via guest agent)"
}
