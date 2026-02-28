locals {
  # Build role-indexed node descriptors
  control_planes = [
    for i in range(var.control_plane_count) : {
      role = "cp"
      idx  = i + 1
      name = format("%s-cp-%02d", var.cluster_name, i + 1)
    }
  ]

  workers = [
    for i in range(var.worker_count) : {
      role = "wk"
      idx  = i + 1
      name = format("%s-wk-%02d", var.cluster_name, i + 1)
    }
  ]

  nodes_all = concat(local.control_planes, local.workers)

  # --- Placement helpers ---
  pve_nodes       = var.proxmox.target_nodes
  pve_nodes_count = length(local.pve_nodes)

  # 1. Placement for Control Planes (stays simple spread/pin)
  target_node_for_cp = {
    for i, n in local.control_planes :
    n.name => local.pve_nodes[i % local.pve_nodes_count]
  }

  pinned_target_node_for = merge([
    for pve, names in try(var.placement.pinned, {}) : {
      for vm_name in names : vm_name => pve
    }
  ]...)

  effective_target_node_for_cp = {
    for n in local.control_planes :
    n.name => (
      var.placement.strategy == "pin" && contains(keys(local.pinned_target_node_for), n.name)
      ? local.pinned_target_node_for[n.name]
      : local.target_node_for_cp[n.name]
    )
  }

  # 2. Calculate remaining capacity for Workers on each node after placing CPs
  requested_vcpu_on_node_cp = {
    for pve in local.pve_nodes :
    pve => sum(concat([0], [
      for n in local.control_planes : var.sizing.control_plane.vcpu
      if local.effective_target_node_for_cp[n.name] == pve
    ]))
  }

  requested_memory_on_node_cp = {
    for pve in local.pve_nodes :
    pve => sum(concat([0], [
      for n in local.control_planes : var.sizing.control_plane.memory
      if local.effective_target_node_for_cp[n.name] == pve
    ]))
  }

  worker_slots_on_node = {
    for pve in local.pve_nodes :
    pve => floor(min(
      (var.pve_capacity[pve].vcpu - local.requested_vcpu_on_node_cp[pve]) / var.sizing.worker.vcpu,
      (var.pve_capacity[pve].memory - local.requested_memory_on_node_cp[pve]) / var.sizing.worker.memory
    ))
  }

  # 3. Generate interleaved available slots for workers
  all_worker_slots = flatten([
    for pve in local.pve_nodes : [
      for i in range(max(0, local.worker_slots_on_node[pve])) : {
        node = pve
        rank = i
      }
    ]
  ])

  interleaved_worker_slots = [
    for s in sort([
      for s in local.all_worker_slots : format("%03d-%s", s.rank, s.node)
    ]) : element(split("-", s), 1)
  ]

  # 4. Placement for Workers (automatically fall back to a node that fits)
  target_node_for_wk = {
    for i, n in local.workers :
    n.name => (
      i < length(local.interleaved_worker_slots)
      ? local.interleaved_worker_slots[i]
      : "insufficient-capacity"
    )
  }

  effective_target_node_for_wk = {
    for n in local.workers :
    n.name => (
      var.placement.strategy == "pin" && contains(keys(local.pinned_target_node_for), n.name)
      ? local.pinned_target_node_for[n.name]
      : local.target_node_for_wk[n.name]
    )
  }

  # Final combined mapping
  effective_target_node_for = merge(local.effective_target_node_for_cp, local.effective_target_node_for_wk)

  # VMID bases (adjust as you like)
  vmid_base = {
    cp = 401
    wk = 501
  }

  # Quick lookup sizing by role
  sizing_by_role = {
    cp = var.sizing.control_plane
    wk = var.sizing.worker
  }

  # Proxmox VLAN id: provider expects int; omit vlan tag if not set
  vlan_id = try(var.proxmox.vlan_id, null)

  #############################################################################
  # ENTERPRISE CAPACITY VALIDATION LOCALS (ADDED)
  #############################################################################

  # Ensure pve_capacity includes every target node
  missing_capacity_nodes = [
    for n in local.pve_nodes : n if !contains(keys(var.pve_capacity), n)
  ]

  # Total requested resources (vCPU, RAM MB)
  requested_total_vcpu = (
    var.control_plane_count * var.sizing.control_plane.vcpu +
    var.worker_count * var.sizing.worker.vcpu
  )

  requested_total_memory = (
    var.control_plane_count * var.sizing.control_plane.memory +
    var.worker_count * var.sizing.worker.memory
  )

  # Total allocatable capacity (for nodes in pool)
  capacity_total_vcpu = sum(concat([0], [
    for n in local.pve_nodes : var.pve_capacity[n].vcpu
  ]))

  capacity_total_memory = sum(concat([0], [
    for n in local.pve_nodes : var.pve_capacity[n].memory
  ]))

  # Per-node requested resources based on planned placement (effective_target_node_for)
  requested_vcpu_on_node = {
    for pve in local.pve_nodes :
    pve => sum(concat([0], [
      for n in local.nodes_all : (n.role == "cp" ? var.sizing.control_plane.vcpu : var.sizing.worker.vcpu)
      if local.effective_target_node_for[n.name] == pve
    ]))
  }

  requested_memory_on_node = {
    for pve in local.pve_nodes :
    pve => sum(concat([0], [
      for n in local.nodes_all : (n.role == "cp" ? var.sizing.control_plane.memory : var.sizing.worker.memory)
      if local.effective_target_node_for[n.name] == pve
    ]))
  }

  remaining_vcpu_on_node = {
    for pve in local.pve_nodes :
    pve => var.pve_capacity[pve].vcpu - local.requested_vcpu_on_node[pve]
  }

  remaining_memory_on_node = {
    for pve in local.pve_nodes :
    pve => var.pve_capacity[pve].memory - local.requested_memory_on_node[pve]
  }
}

resource "terraform_data" "capacity_assertions" {
  input = {
    cluster_name           = var.cluster_name
    requested_total_vcpu   = local.requested_total_vcpu
    requested_total_memory = local.requested_total_memory
    capacity_total_vcpu    = local.capacity_total_vcpu
    capacity_total_memory  = local.capacity_total_memory
  }

  lifecycle {
    precondition {
      condition     = length(local.missing_capacity_nodes) == 0
      error_message = "pve_capacity missing entries for target nodes: ${join(", ", local.missing_capacity_nodes)}"
    }

    precondition {
      condition     = local.requested_total_vcpu <= local.capacity_total_vcpu
      error_message = "Insufficient TOTAL vCPU budget. Requested=${local.requested_total_vcpu}, Available=${local.capacity_total_vcpu}."
    }

    precondition {
      condition     = local.requested_total_memory <= local.capacity_total_memory
      error_message = "Insufficient TOTAL RAM budget (MB). Requested=${local.requested_total_memory}, Available=${local.capacity_total_memory}."
    }

    precondition {
      condition     = length(local.interleaved_worker_slots) >= var.worker_count
      error_message = "Not enough total capacity across all nodes to fit ${var.worker_count} workers after placing control planes. Only ${length(local.interleaved_worker_slots)} worker slots available."
    }

    precondition {
      condition = alltrue([
        for n in local.pve_nodes :
        local.requested_vcpu_on_node[n] <= var.pve_capacity[n].vcpu
      ])
      error_message = "Insufficient vCPU on at least one Proxmox node for the planned placement. Adjust pve_capacity / placement / sizing."
    }

    precondition {
      condition = alltrue([
        for n in local.pve_nodes :
        local.requested_memory_on_node[n] <= var.pve_capacity[n].memory
      ])
      error_message = "Insufficient RAM on at least one Proxmox node for the planned placement. Adjust pve_capacity / placement / sizing."
    }
  }
}

resource "proxmox_vm_qemu" "control_plane" {
  depends_on = [
    terraform_data.capacity_assertions,
    proxmox_storage_iso.talos
  ]

  for_each = { for n in local.control_planes : n.name => n }

  target_node = local.effective_target_node_for[each.key]
  description = "Talos Control Plane (${var.cluster_name})"
  vmid        = local.vmid_base.cp + (each.value.idx - 1)
  name        = each.key
  tags = "control-plane,${var.cluster_name}"

  memory  = local.sizing_by_role.cp.memory
  balloon = 0

  cpu {
    cores   = local.sizing_by_role.cp.vcpu
    sockets = 1
    type    = "host"
  }

  disk {
    slot     = "scsi0"
    type     = "disk"
    storage  = var.proxmox.datastore_id
    size     = "${local.sizing_by_role.cp.disk}G"
    iothread = true
    format   = "raw"
    cache    = "writethrough"
  }

  agent     = 1
  skip_ipv6 = true

  bios    = "ovmf"
  machine = "q35"

  network {
    id     = 0
    bridge = var.proxmox.bridge
    model  = "virtio"

    # only set if provided
    tag = local.vlan_id
  }

  scsihw = "virtio-scsi-pci"

  # Talos ISO as CD-ROM (generated via Talos Image Factory)
  disk {
    slot = "ide2"
    type = "cdrom"
    iso  = "${proxmox_storage_iso.talos[local.effective_target_node_for[each.key]].storage}:iso/${proxmox_storage_iso.talos[local.effective_target_node_for[each.key]].filename}"
  }

  efidisk {
    efitype           = "4m"
    storage           = var.proxmox.datastore_id
    pre_enrolled_keys = false
  }

  rng {
    source = "/dev/urandom"
  }

  boot     = "order=scsi0;ide2"
  bootdisk = "scsi0"

  lifecycle {
    ignore_changes = [disk]
  }
}

resource "proxmox_vm_qemu" "worker" {
  depends_on = [
    proxmox_vm_qemu.control_plane
  ]
  for_each = { for n in local.workers : n.name => n }

  target_node = local.effective_target_node_for[each.key]
  description = "Talos Worker (${var.cluster_name})"
  vmid        = local.vmid_base.wk + (each.value.idx - 1)
  name        = each.key
  tags = "worker,${var.cluster_name}"

  memory  = local.sizing_by_role.wk.memory
  balloon = 0

  cpu {
    cores   = local.sizing_by_role.wk.vcpu
    sockets = 1
    type    = "host"
  }

  disk {
    slot     = "scsi0"
    type     = "disk"
    storage  = var.proxmox.datastore_id
    size     = "${local.sizing_by_role.wk.disk}G"
    iothread = true
    format   = "raw"
    cache    = "writethrough"
  }

  agent     = 1
  skip_ipv6 = true

  bios    = "ovmf"
  machine = "q35"

  network {
    id     = 0
    bridge = var.proxmox.bridge
    model  = "virtio"
    tag    = local.vlan_id
  }

  scsihw = "virtio-scsi-pci"

  disk {
    slot = "ide2"
    type = "cdrom"
    iso  = "${proxmox_storage_iso.talos[local.effective_target_node_for[each.key]].storage}:iso/${proxmox_storage_iso.talos[local.effective_target_node_for[each.key]].filename}"
  }

  efidisk {
    efitype           = "4m"
    storage           = var.proxmox.datastore_id
    pre_enrolled_keys = false
  }

  rng {
    source = "/dev/urandom"
  }

  boot     = "order=scsi0;ide2"
  bootdisk = "scsi0"

  lifecycle {
    ignore_changes = [disk]
  }
}

resource "terraform_data" "iso_detach" {
  depends_on = [
    proxmox_vm_qemu.control_plane,
    proxmox_vm_qemu.worker
  ]
  for_each = merge(proxmox_vm_qemu.control_plane, proxmox_vm_qemu.worker)

  input = {
    vmid        = each.value.vmid
    target_node = each.value.target_node
    ip          = each.value.default_ipv4_address
    name        = each.value.name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    environment = {
      PVE_TOKEN = nonsensitive("${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}")
      PVE_URL   = var.proxmox_api_url
    }
    command = <<EOT
      set -e
      echo "IP ${self.input.ip} obtained for ${self.input.name}. Detaching ISO..."
      sleep 2
      curl -k -S -s -X PUT -H "Authorization: PVEAPIToken=$PVE_TOKEN" \
        "$PVE_URL/nodes/${self.input.target_node}/qemu/${self.input.vmid}/config" \
        -d "ide2=none"
    EOT
  }
}

output "capacity_remaining_by_node" {
  value = {
    for n in local.pve_nodes : n => {
      requested_vcpu   = local.requested_vcpu_on_node[n]
      requested_memory = local.requested_memory_on_node[n]
      capacity_vcpu    = var.pve_capacity[n].vcpu
      capacity_memory  = var.pve_capacity[n].memory
      remaining_vcpu   = local.remaining_vcpu_on_node[n]
      remaining_memory = local.remaining_memory_on_node[n]
    }
  }
}

output "ip_by_control_plane" {
  value = {
    for n in local.control_planes : n.name => {
      ip = proxmox_vm_qemu.control_plane[n.name].default_ipv4_address
    }
  }
  description = "DHCP IPv4 address for control plane reported by Proxmox provider (usually via guest agent)"
}

output "ip_by_worker" {
  value = {
    for n in local.workers : n.name => {
      ip = proxmox_vm_qemu.worker[n.name].default_ipv4_address
    }
  }
  description = "DHCP IPv4 address for worker reported by Proxmox provider (usually via guest agent)"
}
