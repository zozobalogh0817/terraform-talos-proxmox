cluster_name        = "talos-lab"
environment         = "lab"
ha_enabled          = true
control_plane_count = 3
worker_count        = 2

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
  iso = "local:iso/talos-qemu-agent-metal-amd64.iso"
  extra_manifests = [
    "https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml",
    "https://github.com/cert-manager/cert-manager/releases/download/v1.19.3/cert-manager.yaml",
    "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.14.3/deploy/static/provider/cloud/deploy.yaml",
    /*
    "https://raw.githubusercontent.com/longhorn/longhorn/v1.11.0/deploy/longhorn.yaml",
    "https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.1/components.yaml"
     */
  ]
}