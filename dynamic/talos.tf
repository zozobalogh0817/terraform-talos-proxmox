resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "control_plane" {
  depends_on = [
    data.talos_image_factory_urls.this
  ]

  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${local.authoritative_endpoint}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = compact([
    yamlencode({
      cluster = {
        inlineManifests = [
          for m in var.talos.inline_manifests : {
            name     = m.name
            contents = file("${path.module}/${m.file}")
          }
        ]
        extraManifests = var.talos.extra_manifests
        apiServer = {
          certSANs = compact([local.authoritative_endpoint])
        }
      }
    }),
    yamlencode({
      machine = merge(
        {
          install = {
            image = data.talos_image_factory_urls.this.urls.installer
          }
          certSANs = compact([local.authoritative_endpoint])
        },
        var.talos.machine
      )
    }),
    # Talos Native VIP configuration
    var.load_balancer.enabled && var.load_balancer.strategy == "talos_native" ? yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              interface = var.load_balancer.interface
              vip = {
                ip   = var.load_balancer.vip
                vrid = var.load_balancer.vrid
              }
            }
          ]
        }
      }
    }) : null
  ])
}

data "talos_machine_configuration" "worker" {
  depends_on = [
    data.talos_image_factory_urls.this
  ]

  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${local.authoritative_endpoint}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    yamlencode({
      machine = merge(
        {
          install = {
            image = data.talos_image_factory_urls.this.urls.installer
          }
          certSANs = compact([local.authoritative_endpoint])
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
  nodes                = [local.authoritative_endpoint]
  endpoints            = local.authoritative_talos_endpoints
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
  node                 = local.authoritative_endpoint
  endpoint             = local.authoritative_endpoint

  depends_on = [
    talos_machine_configuration_apply.control_plane,
    talos_machine_configuration_apply.worker
  ]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.authoritative_endpoint
  endpoint             = local.authoritative_endpoint

  depends_on = [
    talos_machine_bootstrap.this
  ]
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "${path.module}/talos/kubeconfig"
}
