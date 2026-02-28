cluster_name        = "talos-lab"
ha_enabled          = false
control_plane_count = 1
worker_count        = 2

proxmox = {
  target_nodes = ["pve1", "pve2", "pve3"]
  datastore_id = "local-lvm"
  bridge       = "vmbr0"
}

placement = {
  strategy = "spread"
}

sizing = {
  control_plane = { vcpu = 4, memory = 4096, disk = 60 }
  worker        = { vcpu = 10, memory = 8192, disk = 80 }
}

pve_capacity = {
  pve1 = { vcpu = 40, memory = 32000 }
  pve2 = { vcpu = 24, memory = 32000 }
  pve3 = { vcpu = 40, memory = 32000 }
}

talos = {
  version  = "v1.12.4"
  platform = "metal"
  arch     = "amd64"
  extra_manifests = [
    "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml",
    "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
  ]
  inline_manifests = [
    {
      name = "argocd-namespace"
      file = "cluster-manifests/argocd-namespace.yaml"
    },
    {
      name = "argocd-controller-crb"
      file = "cluster-manifests/argocd-controller-crb.yaml"
    },
    {
      name = "argocd-installer"
      file = "cluster-manifests/argocd-installer.yaml"
    },
    {
      name = "argocd-root-app"
      file = "cluster-manifests/argocd-root-app.yaml"
    }
  ]
  extensions = [
    "siderolabs/qemu-guest-agent",
    "siderolabs/iscsi-tools",
    "siderolabs/util-linux-tools",
  ]
  machine = {
    kubelet = {
      extraArgs = {
        rotate-server-certificates = true
      },
      extraMounts = [
        {
          destination = "/var/lib/longhorn"
          type        = "bind"
          source      = "/var/lib/longhorn"
          options     = ["bind", "rshared", "rw"]
        }
      ]
    }
  }
}

load_balancer = {
  enabled  = true
  strategy = "haproxy" # Dedicated Load Balancer (VM-based)
  vip      = "192.168.88.200"
  nodes = {
    load-balancer-1 = { target_node = "pve1", ip = "192.168.88.201", id = 801 }
    load-balancer-2 = { target_node = "pve2", ip = "192.168.88.202", id = 802 }
  }
  template = "alpine-lb-template"
  template_ids = {
    pve1 = "alpine-lb-template"
    pve2 = "alpine-lb-template"
    pve3 = "alpine-lb-template"
  }
  cores                = 1
  memory               = 512
  disk                 = 2
  gateway              = "192.168.88.1"
  ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq+eb7lneZK43dqBErMIAUHOmDRiSWMNgNQoOBdqJcW"
  ssh_private_key_path = "./id_ed25519"
}
