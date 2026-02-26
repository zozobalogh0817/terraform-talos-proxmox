cluster_name        = "talos-lab"
environment         = "lab"
ha_enabled          = true
control_plane_count = 3
worker_count        = 6

proxmox = {
  endpoint     = "https://192.168.88.64:8006"
  insecure     = true
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
    "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml",
    "https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml"
  ]
  inline_manifests = [
    {
      name = "metallb-config"
      file = "cluster-manifests/metallb-config.yaml"
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
