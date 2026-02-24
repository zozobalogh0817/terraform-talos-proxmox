resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "control_plane" {
  depends_on = [
    data.talos_image_factory_urls.this
  ]

  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${proxmox_vm_qemu.control_plane[local.control_planes[0].name].default_ipv4_address}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    yamlencode({
      cluster = {
        inlineManifests = [
          for m in var.talos.inline_manifests : {
            name     = m.name
            contents = file("${path.module}/${m.file}")
          }
        ]
        extraManifests = var.talos.extra_manifests
      }
    }),
    yamlencode({
      machine = merge(
        {
          install = {
            image = data.talos_image_factory_urls.this.urls.installer
          }
        },
        var.talos.machine
      )
    })
  ]
}

data "talos_machine_configuration" "worker" {
  depends_on = [
    data.talos_image_factory_urls.this
  ]

  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${proxmox_vm_qemu.control_plane[local.control_planes[0].name].default_ipv4_address}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    yamlencode({
      machine = merge(
        {
          install = {
            image = data.talos_image_factory_urls.this.urls.installer
          }
        },
        var.talos.machine
      )
    })
  ]
}

data "talos_client_configuration" "this" {
  depends_on = [
    proxmox_vm_qemu.control_plane
  ]

  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [proxmox_vm_qemu.control_plane[local.control_planes[0].name].default_ipv4_address]
  endpoints            = [for cp in local.control_planes : proxmox_vm_qemu.control_plane[cp.name].default_ipv4_address]
}

resource "local_file" "secrets_yaml" {
  content  = yamlencode(talos_machine_secrets.this.machine_secrets)
  filename = "${path.module}/talos/secrets.yaml"
}

resource "local_file" "control_plane_yaml" {
  content  = data.talos_machine_configuration.control_plane.machine_configuration
  filename = "${path.module}/talos/control-plane.yaml"
}

resource "local_file" "worker_yaml" {
  content  = data.talos_machine_configuration.worker.machine_configuration
  filename = "${path.module}/talos/worker.yaml"
}

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.module}/talos/talosconfig"
}

resource "talos_machine_configuration_apply" "control_plane" {
  for_each                    = proxmox_vm_qemu.control_plane
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane.machine_configuration
  node                        = each.value.default_ipv4_address
  endpoint                    = each.value.default_ipv4_address

  depends_on = [
    data.talos_client_configuration.this
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each                    = proxmox_vm_qemu.worker
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.default_ipv4_address
  endpoint                    = each.value.default_ipv4_address

  depends_on = [
    talos_machine_configuration_apply.control_plane
  ]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = proxmox_vm_qemu.control_plane[local.control_planes[0].name].default_ipv4_address
  endpoint             = proxmox_vm_qemu.control_plane[local.control_planes[0].name].default_ipv4_address

  depends_on = [
    talos_machine_configuration_apply.control_plane,
    talos_machine_configuration_apply.worker
  ]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = proxmox_vm_qemu.control_plane[local.control_planes[0].name].default_ipv4_address
  endpoint             = proxmox_vm_qemu.control_plane[local.control_planes[0].name].default_ipv4_address

  depends_on = [
    talos_machine_bootstrap.this
  ]
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "${path.module}/talos/kubeconfig"
}
