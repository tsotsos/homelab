# 🏠 Homelab Infrastructure

Enterprise-grade Kubernetes homelab with Talos Linux, GitOps, and comprehensive application stack.

## 🚀 Quick Start

### Prerequisites

- **3 Proxmox VE nodes** in cluster
- **Talos Linux ISO** uploaded to Proxmox
- **Network**: VLAN configured, static IPs available (10.0.2.0/24)
- **Tools**: terraform, talosctl, kubectl, helm, kustomize, yq, jq

### Deployment Steps

```bash
# 1. Configure cluster (edit cluster-config.yaml)
cd infra/
vi cluster-config.yaml  # Set your IPs, MACs, Proxmox nodes

# 2. Deploy infrastructure
terraform init
terraform apply

# 3. Deploy Talos cluster
cd ../scripts/
./deploy.sh

# 4. Bootstrap core services (Cilium + ArgoCD)
./bootstrap.sh

# 5. Check status
./deploy.sh status
kubectl get nodes -o wide
```

**What gets deployed:**
- ✅ 9 VMs (3 control plane + 6 workers)
- ✅ Talos Linux installed to disk
- ✅ Kubernetes cluster bootstrapped
- ✅ Cilium CNI (1.18.4)
- ✅ ArgoCD GitOps (auto-deploys from `cluster/`)
- ✅ Talos VIP (10.0.2.100) for HA

## 📁 Repository Structure

```
homelab/
├── 📖 README.md                    # This overview + deployment guide
├── 🏗️ infra/                       # Infrastructure (Terraform + Talos)
│   ├── README.md                   # Detailed infrastructure docs
│   ├── cluster-config.yaml         # Single source of truth (YAML)
│   ├── main.tf                     # Terraform infrastructure
│   ├── terraform.tfvars.example    # Example configuration
│   └── talos-config/              # Generated configs (ignored in git)
├── 📦 apps/                        # Helm charts & app definitions
│   ├── argocd/                    # GitOps controller
│   ├── cert-manager/              # Certificate management
│   ├── external-dns/              # DNS automation
│   ├── ingress-nginx/             # Ingress controller
│   ├── kube-vip-cloud-provider/   # LoadBalancer provider
│   ├── longhorn/                  # Storage solution
│   ├── rancher/                   # Kubernetes management
│   └── sealed-secrets/            # Secret encryption
├── 🎯 cluster/                     # Cluster-specific manifests
│   ├── argocd/                    # ArgoCD config overlays
│   ├── cert-manager/              # Cert-Manager + ClusterIssuer
│   ├── external-dns/              # External-DNS config
│   ├── ingress-nginx/             # Ingress config overlays
│   ├── kube-vip-cloud-provider/   # LoadBalancer IP pool
│   ├── sealed-secrets/            # Sealed secret overlays
│   ├── kustomization.yaml         # Root kustomization
│   └── main.yaml                  # ArgoCD App-of-Apps
└── 📜 scripts/                     # Deployment & utility scripts
    ├── bootstrap.sh               # Install Cilium + ArgoCD
    ├── deploy.sh                  # Deploy Talos cluster
    ├── label-nodes.sh             # Apply node labels
    └── sealed-secrets.sh          # Manage sealed secrets
```

## ✨ Features

- **🏗️ Infrastructure as Code**: Terraform-managed Proxmox VMs
- **⚡ Fast Deployment**: 15-20 mins total (parallel node configuration)
- **🔧 Per-VM Customization**: Individual CPU, RAM, disk per node
- **🌐 Single Config File**: cluster-config.yaml drives everything
- **🛡️ Security First**: Sealed secrets, RBAC, kernel hardening
- **📊 GitOps Ready**: ArgoCD auto-deploys from `cluster/`
- **🏥 Production-Grade**: HA control plane, etcd, Cilium CNI

## 🎯 Core Stack

| Component | Purpose | Version | Status |
|-----------|---------|---------|--------|
| **Talos Linux** | Immutable OS | v1.11.5 | ✅ |
| **Kubernetes** | Orchestration | v1.34.1 | ✅ |
| **Cilium** | CNI + networking | 1.18.4 | ✅ |
| **ArgoCD** | GitOps | 8.2.5 | ✅ |
| **Cert-Manager** | TLS certificates | Latest | ✅ |
| **Ingress-NGINX** | Load balancing | Latest | ✅ |
| **Sealed-Secrets** | Secret encryption | 2.17.9 | ✅ |

## 📋 Architecture

**Cluster:** 9 VMs across 3 Proxmox hosts
- **Control Plane**: 3 nodes (10.0.2.101-103) - 4 vCPU, 8GB RAM, 150GB disk, 20GB etcd
- **Workers**: 6 nodes (10.0.2.104-109) - 3-4 vCPU, 8-12GB RAM, 150GB disk
  - Workers 1-3: Infrastructure & apps workloads
  - Workers 4-6: Storage nodes with 1TB additional disk for Longhorn

**Network:**
- VLAN: vmbr1 (10.0.2.0/24)
- VIP: 10.0.2.100 (Talos built-in HA)
- LoadBalancer Pool: 10.0.2.75-99
- DNS: Cloudflare (1.1.1.1, 8.8.8.8)

## 📋 Prerequisites

- **Proxmox VE**: 3-node cluster (s01, s02, s03) with 16 cores, 62GB RAM each
- **Talos ISO**: v1.11.5 uploaded to Proxmox storage
- **Network**: VLAN on vmbr1, 10.0.2.0/24 subnet configured
- **Storage**: `local-lvm` (826GB) + `zfs-pool` per host
- **Tools**: terraform, talosctl, kubectl, helm, kustomize, yq, jq

## 🚀 Getting Started

### 1. Configure Cluster

Edit `infra/cluster-config.yaml` (single source of truth):

```yaml
cluster:
  name: "kng-cluster"
  vip: "10.0.2.100"
  use_talos_vip: true        # Built-in HA
  use_static_ips: true       # Not DHCP
  cni: "none"                # Cilium installed post-bootstrap

nodes:
  "kng-cp-1":
    vm_id: 801
    ip_address: "10.0.2.101"
    mac_address: "02:00:00:00:01:01"
    proxmox_node: "s01"
    role: "controlplane"
    cpu_cores: 4
    # ... more nodes ...
```

Also create `infra/terraform.tfvars` with Proxmox credentials (see `terraform.tfvars.example`).

### 2. Deploy Infrastructure

```bash
cd infra/
terraform init
terraform plan          # Review changes
terraform apply         # Creates VMs + generates Talos configs
```

**Output:**
- 9 VMs created on Proxmox (3 per host, balanced distribution)
- Talos machine configs in `talos-config/` directory
- `talosconfig` client configuration file

### 3. Deploy Talos Cluster

```bash
cd ../scripts/
./deploy.sh
```

**What it does:**
1. Applies Talos machine configs to all VMs
2. Waits for nodes to be ready (2-5 mins per node)
3. Bootstraps Kubernetes on first control plane
4. Retrieves kubeconfig to `infra/talos-config/kubeconfig`

**Result:** Kubernetes cluster running, nodes will be **NotReady** (no CNI yet)

### 4. Bootstrap Core Services

```bash
./bootstrap.sh
```

**What it installs:**
1. **Cilium CNI** (1.18.4) - Nodes become Ready
2. **ArgoCD** - GitOps controller
3. **App-of-Apps** - Auto-deploys everything in `cluster/` directory

### 5. Verify Deployment

```bash
./deploy.sh status                 # Cluster overview
kubectl get nodes -o wide          # Node status
kubectl get pods -A                # All pods
kubectl get applications -n argocd # ArgoCD apps
```

### 6. Access ArgoCD

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0

# Access at https://localhost:8080
# Username: admin
# Password: (from command above)
```

## 🔧 Operations

### Deployment Scripts

```bash
# Deploy cluster (from scratch or redeploy)
cd scripts/
./deploy.sh              # Full: apply + bootstrap
./deploy.sh apply        # Just install Talos to VMs
./deploy.sh bootstrap    # Just bootstrap K8s
./deploy.sh status       # Check cluster health

# Bootstrap services (Cilium + ArgoCD)
./bootstrap.sh           # Full bootstrap
./bootstrap.sh cilium    # Only Cilium CNI
./bootstrap.sh argocd    # Only ArgoCD (requires Cilium)

# Manage sealed secrets
./sealed-secrets.sh all       # Install controller + seal secrets
./sealed-secrets.sh validate  # Check unsealed secrets
./sealed-secrets.sh seal      # Encrypt secrets
./sealed-secrets.sh unseal    # Decrypt secrets
```

### Managing Secrets

**Never commit actual secrets to git!** Use sealed-secrets:

```bash
cd scripts/

# 1. Edit unsealed secrets in secrets-un/
vi ../secrets-un/cert-manager.yaml
vi ../secrets-un/external-dns.yaml

# 2. Validate format
./sealed-secrets.sh validate

# 3. Seal secrets (encrypts with cluster public key)
./sealed-secrets.sh seal

# 4. Sealed secrets are written to cluster/*/sealed-secret.yaml
# 5. Commit sealed secrets (safe to push to git)
git add ../cluster/*/sealed-secret.yaml
git commit -m "Update sealed secrets"
```

### Talos Operations

```bash
export TALOSCONFIG="infra/talos-config/talosconfig"

# Check node status
talosctl --nodes 10.0.2.101 version
talosctl --nodes 10.0.2.101,10.0.2.102,10.0.2.103 health

# View logs
talosctl --nodes 10.0.2.101 logs
talosctl --nodes 10.0.2.101 dmesg

# Node operations
talosctl --nodes 10.0.2.101 reboot
talosctl --nodes 10.0.2.101 shutdown
talosctl --nodes 10.0.2.101 reset  # ⚠️ Destructive!

# Check etcd cluster
talosctl --nodes 10.0.2.101 etcd members
```

### Scaling

```bash
# Scale worker nodes (edit cluster-config.yaml first)
cd infra/
vi cluster-config.yaml  # Add new worker node definition
terraform apply         # Creates new VM
cd ../scripts/
# Apply config to new node manually with talosctl apply-config
```

## 🛡️ Security

- **Immutable OS**: Talos Linux with read-only root filesystem
- **No SSH by default**: API-only access via mutual TLS
- **Kernel Hardening**: Optimized kernel parameters (no idle=poll!)
- **RBAC**: Role-based access control enabled
- **Sealed Secrets**: Secrets encrypted with cluster-specific keys
- **Certificate Management**: Automated via cert-manager + Let's Encrypt
- **Network Policies**: Ready for implementation

## � Troubleshooting

### Nodes Not Ready After Bootstrap

This is **expected**! Nodes will be NotReady until Cilium CNI is installed.

```bash
cd scripts/
./bootstrap.sh  # Installs Cilium
```

### Certificate Errors

**Never regenerate Talos certificates manually!** Always use Terraform-generated configs.

```bash
cd infra/
terraform apply -auto-approve -target=local_file.talosconfig
```

### High CPU Usage on Proxmox Hosts

Check kernel arguments in `cluster-config.yaml`. Remove aggressive CPU settings:

```yaml
defaults:
  talos:
    kernel_args:
      - "mitigations=off"     # Safe for homelab
      - "clocksource=tsc"     # Efficient timekeeping
      - "tsc=reliable"        # Trust TSC
      # ❌ DO NOT USE: "idle=poll" or "processor.max_cstate=1"
      # These cause 100% CPU polling!
```

### Nodes Not Installing Talos

Check VM console in Proxmox:
- ISO properly mounted?
- Network configured?
- UEFI boot working?
- Sufficient disk space (150GB)?

### Sealed Secrets Not Decrypting

Sealed secrets are encrypted with cluster-specific public key. If cluster was rebuilt:

```bash
cd scripts/
# Re-seal with new cluster key
./sealed-secrets.sh seal
git add ../cluster/*/sealed-secret.yaml
git commit -m "Re-seal secrets for new cluster"
```

### Check Deployment Logs

```bash
# Talos logs
export TALOSCONFIG="infra/talos-config/talosconfig"
talosctl --nodes 10.0.2.101 logs

# Kubernetes events
kubectl get events -A --sort-by='.lastTimestamp'

# Pod logs
kubectl logs -n kube-system -l k8s-app=cilium
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

---

**🎉 Ready to deploy your enterprise-grade homelab!**

Start with the [Infrastructure Documentation](./infra/README.md) for complete setup instructions.