###############################################################################
# Architectural Alignment (Integration with Talos)
###############################################################################

locals {
  # Determine the authoritative endpoint for the cluster
  # If LB is enabled, we use the VIP. Otherwise, we fallback to the first CP node's IP.
  authoritative_endpoint = var.load_balancer.enabled ? var.load_balancer.vip : (length(proxmox_vm_qemu.control_plane) > 0 ? proxmox_vm_qemu.control_plane[local.control_planes[0].name].default_ipv4_address : "127.0.0.1")

  # List of endpoints for Talos client config
  authoritative_talos_endpoints = var.load_balancer.enabled ? [var.load_balancer.vip] : [for cp in local.control_planes : proxmox_vm_qemu.control_plane[cp.name].default_ipv4_address]

  # Filtered nodes for the dedicated load balancer
  load_balancer_nodes = (var.load_balancer.enabled && var.load_balancer.strategy == "haproxy") ? var.load_balancer.nodes : {}
}

###############################################################################
# Load Balancer Infrastructure (VMs from Packer Template)
# No seeding needed: templates are created manually with Packer on each node.
###############################################################################

resource "proxmox_vm_qemu" "load_balancer" {
  for_each = local.load_balancer_nodes

  name        = "${var.cluster_name}-${each.key}"
  target_node = each.value.target_node
  vmid        = each.value.id
  
  # Use node-specific template ID if available, otherwise fallback to template name
  clone       = lookup(var.load_balancer.template_ids, each.value.target_node, var.load_balancer.template)
  
  full_clone  = true
  
  cpu {
    cores   = var.load_balancer.cores
    sockets = 1
    type    = "host"
  }
  memory  = var.load_balancer.memory
  
  os_type = "cloud-init"
  
  scsihw = "virtio-scsi-single"
  boot     = "order=scsi0;ide2"
  bootdisk = "scsi0"

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = var.proxmox.datastore_id
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size     = "${var.load_balancer.disk}G"
          storage  = var.proxmox.datastore_id
          iothread = true
          format   = "raw"
        }
      }
    }
  }

  network {
    id     = 0
    bridge = var.proxmox.bridge
    model  = "virtio"
    tag    = var.proxmox.vlan_id
  }

  # Cloud-init settings
  ipconfig0 = "ip=${each.value.ip}/32,gw=${var.load_balancer.gateway}"
  sshkeys   = var.load_balancer.ssh_public_key
  
  agent = 1

  lifecycle {
    ignore_changes = [network, disks]
  }
}

###############################################################################
# Provisioning (HAProxy & Keepalived Configuration)
###############################################################################

resource "terraform_data" "load_balancer_config" {
  for_each = local.load_balancer_nodes

  depends_on = [
    proxmox_vm_qemu.load_balancer,
    proxmox_vm_qemu.control_plane
  ]

  input = {
    load_balancer_ip = each.value.ip
    vip   = var.load_balancer.vip
    role  = each.key == keys(var.load_balancer.nodes)[0] ? "MASTER" : "BACKUP"
    prio  = each.key == keys(var.load_balancer.nodes)[0] ? 101 : 100
    cp_ips = [for n in proxmox_vm_qemu.control_plane : n.default_ipv4_address]
  }

  connection {
    port = 2222
    type        = "ssh"
    user        = "alpine" # Default user for Alpine cloud images (configured in setup.sh)
    private_key = file(var.load_balancer.ssh_private_key_path)
    host        = self.input.load_balancer_ip
    agent       = false
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Applying pre-installed HAProxy & Keepalived configuration...'",
      <<-EOT
      # Configure HAProxy
      sudo mkdir -p /run/haproxy
      sudo chown haproxy:haproxy /run/haproxy
      sudo chmod 750 /run/haproxy
      cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
      global
          log /dev/log local0
          log /dev/log local1 notice
          chroot /var/lib/haproxy
          stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
          stats timeout 30s
          user haproxy
          group haproxy
          daemon

      defaults
          log global
          mode tcp
          option tcplog
          timeout connect 5000
          timeout client 50000
          timeout server 50000

      frontend k8s-api
          bind *:6443
          default_backend k8s-api-nodes

      backend k8s-api-nodes
          balance roundrobin
          option tcp-check
          ${join("\n          ", [for i, ip in compact(self.input.cp_ips) : "server cp${i} ${ip}:6443 check"])}

      frontend talos-api
          bind *:50000
          default_backend talos-api-nodes

      backend talos-api-nodes
          balance roundrobin
          option tcp-check
          ${join("\n          ", [for i, ip in compact(self.input.cp_ips) : "server cp${i} ${ip}:50000 check"])}
      EOF
      sudo chmod 644 /etc/haproxy/haproxy.cfg
      sudo chown root:root /etc/haproxy/haproxy.cfg

      # Configure Keepalived
      sudo mkdir -p /etc/keepalived
      cat <<EOF | sudo tee /etc/keepalived/keepalived.conf
      vrrp_instance VI_1 {
          state ${self.input.role}
          interface eth0
          virtual_router_id ${var.load_balancer.vrid}
          priority ${self.input.prio}
          advert_int 1
          authentication {
              auth_type PASS
              auth_pass talos-secret
          }
          virtual_ipaddress {
              ${self.input.vip}
          }
      }
      EOF
      sudo chmod 644 /etc/keepalived/keepalived.conf
      sudo chown root:root /etc/keepalived/keepalived.conf

      sudo rc-update add haproxy default
      sudo rc-update add keepalived default
      sudo rc-service haproxy restart && sudo rc-service keepalived restart
      EOT
    ]
  }
}
