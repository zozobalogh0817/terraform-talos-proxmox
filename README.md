# Enterprise Talos on Proxmox Automation

This repository provides a production-grade Terraform-based framework for the automated deployment and lifecycle management of Talos Linux clusters on Proxmox Virtual Environment (VE). The solution is designed with enterprise requirements in mind, focusing on resource efficiency, predictable placement, and a fully automated "zero-touch" bootstrapping process.

## Architecture and Logic Flow

The deployment architecture is built upon a deterministic dependency chain, ensuring that infrastructure is validated, provisioned, and configured in a logical sequence.

### Deployment Stages

1.  **Capacity Validation**: Before any resource creation occurs, the system evaluates the requested cluster sizing against the available physical capacity defined in `pve_capacity`. This prevents partial deployments that would later fail due to resource exhaustion.
2.  **Infrastructure Provisioning**:
    - **Control Plane Nodes**: Provisioned first to establish the cluster quorum. These nodes are distributed according to the selected placement strategy.
    - **Worker Nodes**: Dynamically assigned to Proxmox nodes based on remaining vCPU and Memory budget after control plane allocation.
3.  **Dynamic Network Discovery**: The solution utilizes the Proxmox Guest Agent to retrieve dynamic IPv4 addresses assigned via DHCP. This eliminates the need for manual IP management while providing the necessary endpoints for Talos configuration.
4.  **Talos Configuration Lifecycle**:
    - **Secrets Management**: Generates unique cluster-wide secrets.
    - **Machine Configuration**: Produces role-specific (controlplane/worker) configurations, dynamically injecting the discovery-derived IP of the primary control plane as the cluster endpoint.
5.  **Cluster Bootstrapping**:
    - Configuration is applied to control plane nodes.
    - Configuration is applied to worker nodes (dependent on control plane readiness).
    - The cluster is initialized (bootstrapped) via the primary control plane node.
6.  **Credential Management**: Upon successful deployment, the `talosconfig` and Kubernetes `kubeconfig` are retrieved and stored locally for administrative use.

### Node Identity and Addressing

To ensure a predictable and manageable infrastructure, each virtual machine is assigned a deterministic VMID based on its role:
- **Control Plane Nodes**: These are assigned VMIDs starting from 401.
- **Worker Nodes**: These are assigned VMIDs starting from 501.

The system relies on the Proxmox Guest Agent being active within the guest operating system. This agent is the primary source of truth for the VM's network identity, allowing Terraform to wait for network availability and retrieve the IP addresses necessary for cluster configuration.

### Resource Dependency Graph

The following diagram illustrates the relationship between the various components and the flow of information from the infrastructure layer to the Kubernetes control plane.

```mermaid
graph TD
    subgraph "Infrastructure Layer (Proxmox)"
        A[Capacity Validation] --> B[Control Plane VMs]
        B --> C[Worker VMs]
        B -- "Guest Agent IP Discovery" --> D[Network Availability]
        C -- "Guest Agent IP Discovery" --> D
    end

    subgraph "Configuration Layer (Talos)"
        D --> E[Secrets Generation]
        E --> F[Machine Configurations]
        F --> G[Local YAML Exports]
    end

    subgraph "Bootstrapping Layer (Kubernetes)"
        G --> H[Apply Config to Control Planes]
        H --> I[Apply Config to Workers]
        H --> J[Cluster Bootstrap]
        J --> K[Kubeconfig Retrieval]
        K --> L[Local Kubeconfig Storage]
    end

    C -.-> |Depends on| B
    I -.-> |Depends on| H
    J -.-> |Depends on| H
    J -.-> |Depends on| I
```

## Implementation Details

### Capacity-Aware Scheduling

The worker placement logic employs an interleaving algorithm to maximize cluster resilience and balance resource utilization:

1.  **Pre-calculation**: The system calculates the aggregate vCPU and Memory requirements for control plane nodes on a per-host basis.
2.  **Slot Allocation**: It determines the number of available "slots" for worker nodes on each physical host by dividing the residual capacity by the worker sizing profile.
3.  **Interleaved Distribution**: Available slots are sorted and interleaved (e.g., Host A - Slot 0, Host B - Slot 0, Host C - Slot 0, Host A - Slot 1...).
4.  **Dynamic Assignment**: Worker nodes are assigned to these interleaved slots sequentially. This ensures that workers are spread as widely as possible across the physical infrastructure, even if some nodes have significantly more capacity than others.

### Automated ISO Detachment

To maintain a clean boot environment and prevent unintended re-installations, the solution automates the removal of the Talos installation media:

- **Mechanism**: A `terraform_data` resource monitors the state of all VM instances.
- **Dependency**: The process is triggered only after the Proxmox provider successfully reports the VM's dynamic IP address, which serves as a proxy for the Guest Agent's readiness.
- **Action**: A `PUT` request is dispatched to the Proxmox API to set the `ide2` CD-ROM drive to `none`.
- **Persistence**: The VM resources use `lifecycle { ignore_changes = [disk] }` to ensure that subsequent Terraform operations do not attempt to revert the ISO detachment.

## Configuration Variables

### Proxmox Infrastructure (`proxmox` object)

- **`endpoint`**: The API endpoint of the Proxmox VE cluster.
- **`insecure`**: Boolean to toggle TLS verification for self-signed certificates.
- **`target_nodes`**: A list of physical host names where VMs can be placed.
- **`datastore_id`**: The Proxmox storage identifier for VM disks.
- **`bridge`**: The network bridge for VM connectivity.
- **`vlan_id`**: Optional VLAN tag for network isolation.

### Cluster Governance and Sizing

- **`cluster_name`**: Logical name for the cluster, used for naming resources and Talos identity.
- **`environment`**: Deployment stage (e.g., `production`, `lab`).
- **`ha_enabled`**: Enforces High Availability constraints (minimum 3 control plane nodes, must be an odd number).
- **`control_plane_count`**: Number of master nodes.
- **`worker_count`**: Number of worker nodes.
- **`pve_capacity`**: A definitive map of physical host resources (vCPU and Memory in MB), used for scheduling validation.
- **`sizing`**: Resource profiles for each node role:
    - `control_plane`: Specifies vCPU cores, Memory (MB), and Disk size (GB).
    - `worker`: Specifies vCPU cores, Memory (MB), and Disk size (GB).

### Placement Policy

- **`placement.strategy`**:
    - `spread`: Evenly distributes VMs across target nodes.
    - `pin`: Respects explicit node assignments defined in the `pinned` mapping.

### Talos Configuration (`talos` object)

- **`iso`**: The path to the Talos Linux ISO image on the Proxmox storage (e.g., `local:iso/talos-1.9.0.iso`).

## Operational Guide

### 1. Preparation

Ensure the Talos Linux ISO is uploaded to your Proxmox ISO datastore and that the Proxmox Guest Agent is included in the boot media.

### 2. Authentication

Configure provider credentials in `dynamic/credentials.auto.tfvars`:

```hcl
proxmox_api_url          = "https://<pve-host>:8006/api2/json"
proxmox_api_token_id     = "terraform-user@pam!tokenid"
proxmox_api_token_secret = "uuid-secret"
```

### 3. Deployment

Execute the Terraform workflow from the `dynamic/` directory:

```bash
terraform init
terraform apply
```

### 4. Cluster Access

Upon completion, all necessary access artifacts are stored in the `./talos/` directory:

- `talosconfig`: Client configuration for `talosctl`.
- `kubeconfig`: Standard Kubernetes configuration for `kubectl`.
- `control-plane.yaml` / `worker.yaml`: Generated machine configurations.
- `secrets.yaml`: Cluster secrets bundle.

## Production Hardening Roadmap

While this solution provides a robust foundation, the following enhancements are recommended for enterprise production environments:

1.  **Remote State Management**: Migrate to a secure remote backend (e.g., S3 with DynamoDB, Terraform Cloud) to ensure state durability and support multi-user workflows.
2.  **Centralized Secret Storage**: Integrate with an enterprise secret manager (e.g., HashiCorp Vault) to remove sensitive credentials from local files.
3.  **Static IP and Load Balancing**: Implement static IP addressing for control plane nodes or deploy a Virtual IP (VIP) solution to ensure a stable and resilient API server endpoint.
4.  **Network Hardening**: Apply granular firewall rules at the Proxmox host level and implement Kubernetes Network Policies to restrict traffic to the management and API ports.
5.  **Observability Integration**: Export Talos and Kubernetes logs/metrics to an enterprise monitoring stack (e.g., ELK, Prometheus/Grafana) for proactive incident management.
6.  **CI/CD Pipeline**: Implement a fully automated deployment pipeline with integrated linting, security scanning, and manual approval gates for production changes.
7.  **Disaster Recovery**: Establish a backup policy using Proxmox Backup Server and implement automated etcd snapshotting.
