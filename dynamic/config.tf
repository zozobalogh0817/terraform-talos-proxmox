###############################################################################
# Cluster intent (governance-level inputs)
###############################################################################

variable "cluster_name" {
  description = "Logical name of the cluster (used for VM names, Talos cluster name, tags)."
  type        = string

  validation {
    condition     = length(var.cluster_name) >= 3 && can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "cluster_name must be at least 3 chars and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "ha_enabled" {
  description = "If true, enforce HA control plane rules (odd and >= 3)."
  type        = bool
  default     = true
}

variable "control_plane_count" {
  description = "Number of control-plane nodes (etcd members)."
  type        = number
  default     = 3

  validation {
    condition = (
      (!var.ha_enabled && var.control_plane_count >= 1) ||
      (var.ha_enabled && var.control_plane_count >= 3 && var.control_plane_count % 2 == 1)
    )
    error_message = "When ha_enabled=true, control_plane_count must be an odd number >= 3 (3,5,7). When ha_enabled=false, it must be >= 1."
  }

  validation {
    condition     = var.control_plane_count <= 7
    error_message = "control_plane_count > 7 is discouraged due to etcd performance."
  }
}
variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 0
    error_message = "worker_count must be >= 0."
  }
}


###############################################################################
# Proxmox placement (you decide where Terraform may place VMs)
###############################################################################

variable "proxmox" {
  description = "Proxmox API + placement targets."
  type = object({
    # Allowed Proxmox nodes (physical hosts) that Terraform may place VMs onto.
    target_nodes = list(string)

    # Where VMs live
    datastore_id = string

    # Network plumbing
    bridge  = string           # e.g. 'vmbr0'
    vlan_id = optional(number) # null means untagged
  })

  validation {
    condition     = length(var.proxmox.target_nodes) >= 1
    error_message = "proxmox.target_nodes must contain at least one Proxmox node."
  }
}

variable "placement" {
  description = "Scheduling policy for VM distribution across Proxmox nodes."
  type = object({
    strategy = string # round_robin | spread | pin
    # Used when strategy == pin: explicit mapping of node name -> list of vm names (optional advanced)
    pinned = optional(map(list(string)), {})
  })
  default = {
    strategy = "spread"
  }

  validation {
    condition     = contains(["round_robin", "spread", "pin"], var.placement.strategy)
    error_message = "placement.strategy must be one of: round_robin, spread, pin."
  }
}

variable "pve_capacity" {
  description = "Per-node allocatable capacity budget for THIS cluster (vCPU + RAM MB). Authoritative for validation."
  type = map(object({
    vcpu   = number
    memory = number # MB
  }))

  validation {
    condition     = length(var.pve_capacity) > 0
    error_message = "pve_capacity must not be empty."
  }
}
###############################################################################
# Node sizing (policy-level: you define the VM shape for each role)
###############################################################################

variable "sizing" {
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
    condition     = var.sizing.control_plane.vcpu >= 2 && var.sizing.control_plane.memory >= 2048 && var.sizing.control_plane.disk >= 20
    error_message = "Control planes must be at least 2 vCPU, 2048MB RAM, 20GB disk (baseline)."
  }

  validation {
    condition     = var.sizing.worker.vcpu >= 1 && var.sizing.worker.memory >= 1024 && var.sizing.worker.disk >= 20
    error_message = "Workers must be at least 1 vCPU, 1024MB RAM, 20GB disk (baseline)."
  }
}

###############################################################################
# Load Balancer Configuration
###############################################################################

variable "load_balancer" {
  description = "Configuration for high-availability load balancer / VIP"
  type = object({
    enabled  = optional(bool, false)
    strategy = optional(string, "haproxy") # talos_native | haproxy | external
    vip      = optional(string, "")

    # --- Talos Native VIP specific ---
    interface = optional(string, "eth0")
    vrid      = optional(number, 51)

    # --- Dedicated Load Balancer specific (VM from Packer Template) ---
    nodes = optional(map(object({
      target_node = string
      ip          = string
      id          = number
    })), {})
    template             = optional(string, "alpine-lb-template")
    template_ids         = optional(map(string), {})
    cores                = optional(number, 1)
    memory               = optional(number, 512)
    disk                 = optional(number, 2)
    gateway              = optional(string, "192.168.88.1")
    ssh_public_key       = optional(string, "")
    ssh_private_key_path = optional(string, "~/.ssh/id_rsa")
  })
  default = {
    enabled  = false
    strategy = "haproxy"
    vip      = ""
    nodes = {
      load-balancer-1 = { target_node = "pve1", ip = "192.168.88.201", id = 801 }
      load-balancer-2 = { target_node = "pve2", ip = "192.168.88.202", id = 802 }
    }
    template             = "alpine-lb-template"
    template_ids = {
      pve1 = "900"
      pve2 = "901"
      pve3 = "902"
    }
    cores                = 1
    memory               = 512
    disk                 = 2
    gateway              = "192.168.88.1"
    ssh_public_key       = ""
    ssh_private_key_path = "~/.ssh/id_rsa"
  }

  validation {
    condition     = contains(["talos_native", "haproxy", "external"], var.load_balancer.strategy)
    error_message = "load_balancer.strategy must be one of: talos_native, haproxy, external."
  }
}

###############################################################################
# Talos image and bootstrap inputs (Talos-specific)
###############################################################################

variable "talos" {
  description = "Talos configuration inputs."
  type = object({
    # Image / boot method
    version         = optional(string, "v1.9.4")
    arch            = optional(string, "amd64")
    platform        = optional(string, "metal")
    extra_manifests  = optional(list(string), [])
    inline_manifests = optional(list(object({
      name = string
      file = string
    })), [])
    extensions       = optional(list(string), [])
    machine          = optional(any, {})
  })
}
