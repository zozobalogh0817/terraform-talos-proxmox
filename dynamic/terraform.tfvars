cluster_identity = {
  name = "talos-lab"
}

cluster_topology = {
  control_plane = {
    replica_count = 3
    availability = {
      mode = "ha"
    }
  }

  worker = {
    replica_count = 3
  }
}

node_profiles = {
  control_plane = {
    vcpu   = 4,
    memory = 4096,
    disk   = 60
  }
  worker = {
    vcpu   = 10,
    memory = 8192,
    disk   = 80
  }
}

infrastructure_policy = {
  node_distribution_strategy = "spread"
}

proxmox_platform = {
  placement_targets = {
    hostnames = ["pve1", "pve2", "pve3"]
  }

  storage = {
    datastore_id = "local-lvm"
  }

  network = {
    bridge = "vmbr0"
  }
}

capacity_budget = {
  pve1 = { vcpu = 40, memory = 32000 }
  pve2 = { vcpu = 24, memory = 32000 }
  pve3 = { vcpu = 40, memory = 32000 }
}

talos = {
  image_factory = {
    version  = "v1.12.4"
    platform = "metal"
    arch     = "amd64"
    strorage = "local"
    extensions = [
      "siderolabs/qemu-guest-agent",
      "siderolabs/iscsi-tools",
      "siderolabs/util-linux-tools",
    ]
  }
  control_plane_machine_config = {
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
    vip = {
      ip        = "192.168.88.200"
      interface = "ens18"
    }
  }
  extra_machine_configuration = {
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
