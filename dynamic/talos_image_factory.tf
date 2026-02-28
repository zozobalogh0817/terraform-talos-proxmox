locals {
  talos_extension_names = [
    for ext in var.talos.image_factory.extensions : split(":", split("/", ext)[length(split("/", ext)) - 1])[0]
  ]
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = var.talos.image_factory.extensions
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos.image_factory.version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = var.talos.image_factory.platform
  architecture  = var.talos.image_factory.arch
}

output "talos_image_factory_urls" {
  value = data.talos_image_factory_urls.this
}

resource "proxmox_storage_iso" "talos" {
  depends_on = [
    data.talos_image_factory_urls.this
  ]

  for_each = toset(var.proxmox_platform.placement_targets.hostnames)

  # Make Proxmox ISO name self-descriptive by including Talos version and extensions
  filename = length(local.talos_extension_names) > 0 ? format("talos-%s-%s.iso", var.talos.image_factory.version, join("_", local.talos_extension_names)) : format("talos-%s.iso", var.talos.image_factory.version)

  pve_node = each.value
  storage  = var.talos.image_factory.storage
  url      = data.talos_image_factory_urls.this.urls.iso
}
