# Infrastructure

**License:** GPL-3.0 - See [LICENSE](../LICENSE)

Terraform automation for deploying Talos Linux Kubernetes cluster on Proxmox VE.

## Prerequisites

**Infrastructure:**
- Proxmox VE cluster (3+ nodes recommended)
- Talos Linux template uploaded to Proxmox
- Network bridge configured (default: vmbr1)
- Storage pools available (local-lvm, etc.)

**Tools:**
```bash
brew install terraform
curl -sL https://talos.dev/install | sh
brew install kubectl helm kustomize yq jq
```

## Configuration

1. **Copy example configs:**
```bash
cp cluster-config.yaml.example cluster-config.yaml
cp terraform.tfvars.example terraform.tfvars
```

2. **Edit cluster-config.yaml:**
Define your cluster nodes with IPs, MACs, roles, CPU, RAM, disk sizes.

3. **Edit terraform.tfvars:**
Add Proxmox endpoint and credentials.

4. **Create secrets.env (gitignored):**
```bash
proxmox_ur=https://proxmox-ip:8006/api2/json
proxmox_user=root@pam
proxmox_secret=your-password
```

## Deployment

```bash
# Source secrets
source ../secrets.env

# Initialize and apply
terraform init
terraform apply

# Outputs generated in talos-config/:
# - talosconfig (Talos CLI config)
# - controlplane.yaml, worker.yaml (machine configs)
# - Kubeconfig (after cluster bootstrap)
```

## Cluster Bootstrap

After Terraform creates VMs:

```bash
cd ../scripts
./deploy.sh          # Applies Talos configs and bootstraps K8s
./bootstrap.sh       # Installs CNI and core components
```

See [scripts/README.md](../scripts/README.md) for details.

## cluster-config.yaml Structure

```yaml
cluster:
  name: "my-cluster"
  vip: "10.0.0.100"
  endpoint: "https://10.0.0.100:6443"
  
  versions:
    talos: "v1.11.5"
    kubernetes: "v1.34.1"

nodes:
  cp-1:
    vm_id: 101
    ip_address: "10.0.0.101"
    mac_address: "BC:24:11:XX:XX:XX"
    proxmox_node: "pve1"
    role: "controlplane"
    cpu: 4
    memory: 8192
    disk_size: 150
    
  worker-1:
    # ... similar structure
```

Each node can have individual resource allocation.

## Talos Configuration

The parser script (`config-parser.sh`) generates:
- Machine configs for control plane and workers
- Talosconfig for CLI access
- Cluster patches (VIP, sysctls, extensions)

Extensions included:
- qemu-guest-agent
- iscsi-tools (for Longhorn)
- util-linux-tools

## Operations

**View cluster status:**
```bash
export TALOSCONFIG=talos-config/talosconfig
talosctl --nodes <NODE_IP> health
talosctl --nodes <NODE_IP> version
```

**Access cluster:**
```bash
export KUBECONFIG=talos-config/kubeconfig
kubectl get nodes -o wide
```

**Upgrade Talos:**
Update `cluster-config.yaml` versions, then:
```bash
terraform apply
talosctl upgrade --image ghcr.io/siderolabs/installer:v1.11.5
```

## Files Generated

- `talos-config/talosconfig` - Talos CLI configuration
- `talos-config/controlplane.yaml` - Control plane machine config
- `talos-config/worker.yaml` - Worker machine config
- `talos-config/kubeconfig` - Kubernetes access (after bootstrap)
- `terraform.tfstate` - Terraform state (gitignored)

## Troubleshooting

**Terraform fails to connect:**
- Check Proxmox credentials in terraform.tfvars
- Verify Proxmox API endpoint is accessible
- Ensure API token has necessary permissions

**VMs created but Talos not applied:**
- Run `../scripts/deploy.sh apply` to push configs
- Check node IPs are reachable from your machine

**Bootstrap fails:**
- Ensure VIP is not in use on network
- Verify cluster endpoint matches VIP in cluster-config.yaml
- Check etcd health: `talosctl --nodes <CP_IP> etcd members`
