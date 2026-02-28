variable "proxmox_url" {
  type = string
}

variable "proxmox_api_token_id" {
  type      = string
  sensitive = true
}

variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

variable "node_vm_ids" {
  type = map(number)
  default = {
    pve1 = 900
    pve2 = 901
    pve3 = 902
  }
}

variable "template_name" {
  type    = string
  default = "alpine-lb-template"
}

variable "template_name_suffix" {
  type    = string
  default = ""
}

variable "template_description" {
  type    = string
  default = "Alpine Linux cloud image with HAProxy, Keepalived, QEMU guest agent, cloud-init and Python."
}

variable "iso_url" {
  type    = string
  default = "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.3-x86_64.iso"
}

variable "iso_checksum" {
  type    = string
  default = "f28171c35bbf623aa3cbaec4b8b29297f13095b892c1a283b15970f7eb490f2d"
}

variable "proxmox_iso_pool" {
  type    = string
  default = "local"
}

variable "proxmox_storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "cores" {
  type    = number
  default = 1
}

variable "memory" {
  type    = number
  default = 512
}

variable "disk_size" {
  type    = string
  default = "2G"
}

variable "ssh_username" {
  type    = string
  default = "root"
}

variable "ssh_password" {
  type    = string
  default = "packer-password"
}
