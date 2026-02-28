# Proxmox API connection
proxmox_url              = "https://192.168.88.64:8006/api2/json"
proxmox_api_token_id     = "root@pam!terraform"
proxmox_api_token_secret = "53f9da24-e541-4a5f-84e2-1bac93b30aaa"

# Template configuration
node_vm_ids = {
  pve1 = 900
  pve2 = 901
  pve3 = 902
}
template_name = "alpine-lb-template"

# ISO configuration
proxmox_iso_pool = "local"
iso_url          = "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.3-x86_64.iso"
iso_checksum     = "f28171c35bbf623aa3cbaec4b8b29297f13095b892c1a283b15970f7eb490f2d"

# VM resources
cores     = 1
memory    = 512
disk_size = "2G"

# SSH credentials for the build process
ssh_username = "root"
ssh_password = "packer-password"
