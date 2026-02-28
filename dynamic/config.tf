###############################################################################
# Cluster intent (governance-level inputs)
###############################################################################

variable "cluster_identity" {
  description = "Logical name of the cluster (used for VM names, Talos cluster name, tags)."
  type        = object({
    name = string
  })

  validation {
    condition     = length(var.cluster_identity.name) >= 3 && can(regex("^[a-z0-9-]+$", var.cluster_identity.name))
    error_message = "cluster_identity.name must be at least 3 chars and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cluster_topology" {
  description = "Cluster topology and control-plane availability policy."
  type = object({
    control_plane = object({
      replica_count = number
      availability = object({
        mode = string # single | ha
      })
    })

    worker = object({
      replica_count = number
    })
  })

  default = {
    control_plane = { replica_count = 3, availability = { mode = "ha" } }
    worker        = { replica_count = 2 }
  }

  validation {
    condition = (
    (var.cluster_topology.control_plane.availability.mode == "single" &&
    var.cluster_topology.control_plane.replica_count >= 1) ||
    (var.cluster_topology.control_plane.availability.mode == "ha" &&
    var.cluster_topology.control_plane.replica_count >= 3 &&
    var.cluster_topology.control_plane.replica_count % 2 == 1)
    )
    error_message = "control_plane.availability.mode=ha requires an odd replica_count >= 3 (3,5,7). mode=single requires replica_count >= 1."
  }

  validation {
    condition     = var.cluster_topology.control_plane.replica_count <= 7
    error_message = "control_plane.replica_count > 7 is discouraged due to etcd performance."
  }

  validation {
    condition     = var.cluster_topology.worker.replica_count >= 0
    error_message = "worker.replica_count must be >= 0."
  }
}

###############################################################################
# Proxmox placement (you decide where Terraform may place VMs)
###############################################################################

variable "proxmox_platform" {
  description = "Proxmox platform contract: placement targets, storage, and network configuration."
  type = object({
    placement_targets = object({
      hostnames = list(string) # allowed Proxmox nodes (physical hosts)
    })

    storage = object({
      datastore_id = string
    })

    network = object({
      bridge  = string           # e.g. vmbr0
      vlan_id = optional(number) # null means untagged
    })
  })

  validation {
    condition     = length(var.proxmox_platform.placement_targets.hostnames) >= 1
    error_message = "proxmox_platform.placement_targets.hostnames must contain at least one Proxmox node."
  }
}

variable "capacity_budget" {
  description = "Per-node allocatable capacity budget for THIS cluster (vCPU + RAM MB). Authoritative for validation."
  type = map(object({
    vcpu   = number
    memory = number # MB
  }))

  validation {
    condition     = length(var.capacity_budget) > 0
    error_message = "pve_capacity must not be empty."
  }
}

variable "infrastructure_policy" {
  description = "Governance policy defining infrastructure distribution and node affinity behavior across Proxmox hosts."
  type = object({
    node_distribution_strategy = string # round_robin | spread | pin

    # Only used when node_distribution_strategy == "pin"
    host_affinity = optional(map(list(string)), {})
  })

  default = {
    node_distribution_strategy = "spread"
  }

  validation {
    condition = contains(
      ["round_robin", "spread", "pin"],
      var.infrastructure_policy.node_distribution_strategy
    )
    error_message = "infrastructure_policy.node_distribution_strategy must be one of: round_robin, spread, pin."
  }
}

###############################################################################
# Node sizing (policy-level: you define the VM shape for each role)
###############################################################################

variable "node_profiles" {
  description = "Resource sizing for Talos nodes."
  type = object({
    control_plane = object({
      vcpu   = number
      memory = number # MB
      disk   = number # GB
    })
    worker = object({
      vcpu   = number
      memory = number # MB
      disk   = number # GB
    })
  })

  # Reasonable Talos/K8s baselines (tune as you like)
  default = {
    control_plane = { vcpu = 2, memory = 4096, disk = 40 }
    worker        = { vcpu = 2, memory = 4096, disk = 40 }
  }

  validation {
    condition     = var.node_profiles.control_plane.vcpu >= 2 && var.node_profiles.control_plane.memory >= 2048 && var.node_profiles.control_plane.disk >= 20
    error_message = "Control planes must be at least 2 vCPU, 2048MB RAM, 20GB disk (baseline)."
  }

  validation {
    condition     = var.node_profiles.worker.vcpu >= 1 && var.node_profiles.worker.memory >= 1024 && var.node_profiles.worker.disk >= 20
    error_message = "Workers must be at least 1 vCPU, 1024MB RAM, 20GB disk (baseline)."
  }
}

###############################################################################
# Talos image and bootstrap inputs (Talos-specific)
###############################################################################

variable "talos" {
  description = "Talos configuration inputs."
  type = object({
    image_factory = object({
      version    = optional(string, "v1.9.4")
      arch       = optional(string, "amd64")
      platform   = optional(string, "metal")
      storage    = optional(string, "local")
      extensions = optional(list(string), [])
    })
    control_plane_machine_config = object({
      extra_manifests = optional(list(string), [])
      inline_manifests = optional(list(object({
        name = string
        file = string
      })), [])
      vip = optional(object({
        ip           = optional(string)
        interface    = optional(string, "ens18")
        dhcp_enabled = optional(bool, true)
      }))
    })
    extra_machine_configuration = optional(any, {})
  })
}
