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
# 1. Configure cluster
cd infra/ && vi cluster-config.yaml  # Set IPs, MACs, Proxmox nodes

# 2. Deploy infrastructure
terraform init && terraform apply

# 3. Deploy Talos cluster
cd ../scripts/ && ./deploy.sh

# 4. Bootstrap all core services
./bootstrap.sh  # ~15-20 minutes

# 5. Verify
kubectl get nodes -o wide && kubectl get pods -A
```

**Result:** Complete Kubernetes cluster with all core infrastructure

📖 **Detailed Guide:** See [BOOTSTRAP.md](BOOTSTRAP.md) for step-by-step bootstrap documentation

## 📁 Repository Structure

```
homelab/
├── README.md                      # This overview
├── BOOTSTRAP.md                   # Detailed bootstrap guide
├── infra/                         # Infrastructure (Terraform + Talos)
│   ├── README.md                  # Infrastructure documentation
│   ├── cluster-config.yaml        # Single source of truth
│   └── talos-config/             # Generated configs
├── cluster/                       # Kubernetes applications (GitOps)
│   ├── README.md                  # Cluster manifests docs
│   ├── main.yaml                  # ArgoCD ApplicationSet root
│   ├── argocd/                   # ArgoCD bootstrap
│   ├── network/                  # CNI, ingress, DNS
│   ├── security/                 # Secrets, certs, auth
│   ├── storage/                  # Longhorn
│   ├── database/                 # PostgreSQL
│   └── observability/            # Monitoring & logging
├── secrets-un/                    # Unsealed secrets (git-ignored)
└── scripts/                       # Deployment scripts
    ├── bootstrap.sh              # Bootstrap infrastructure
    ├── deploy.sh                 # Deploy Talos cluster
    └── README.md                 # Scripts documentation
```

📖 **Detailed Docs:** Each directory has its own README with specific documentation

## ✨ Features

- **🏗️ Infrastructure as Code**: Terraform-managed Proxmox VMs
- **⚡ Fast Deployment**: 15-20 mins total (parallel node configuration)
- **🔧 Per-VM Customization**: Individual CPU, RAM, disk per node
- **🌐 Single Config File**: cluster-config.yaml drives everything
- **🛡️ Security First**: Sealed secrets, RBAC, kernel hardening
- **📊 GitOps Ready**: ArgoCD auto-deploys from `cluster/`
- **🏥 Production-Grade**: HA control plane, etcd, Cilium CNI

## 🎯 Core Stack

| Component | Purpose | Status |
|-----------|---------|--------|
| **Talos Linux** | Immutable OS | ✅ |
| **Kubernetes** | Orchestration | ✅ |
| **Cilium** | CNI + Ingress | ✅ |
| **ArgoCD** | GitOps | ✅ |
| **Kube-VIP** | LoadBalancer | ✅ |
| **Sealed-Secrets** | Secret encryption | ✅ |
| **Cert-Manager** | TLS automation | ✅ |
| **Longhorn** | Distributed storage | ✅ |
| **Loki + Alloy** | Log aggregation | ✅ |
| **Prometheus Stack** | Monitoring | ✅ |

📖 **See:** [BOOTSTRAP.md](BOOTSTRAP.md) for detailed component installation steps

## 📋 Architecture

**Cluster:** 9 VMs across 3 Proxmox hosts
- **Control Plane**: 3 nodes - 4 vCPU, 8GB RAM, 150GB disk, 20GB etcd
- **Workers**: 6 nodes - 3-4 vCPU, 8-12GB RAM, 150GB disk
  - Workers 1-3: Infrastructure & apps workloads
  - Workers 4-6: Storage nodes with additional disk for Longhorn

**Network:**
- VLAN: Configured on Proxmox bridge
- VIP: High availability via Talos built-in VIP
- LoadBalancer Pool: Kube-VIP cloud provider
- DNS: Configured per environment

## 📋 Prerequisites

- **Proxmox VE**: 3-node cluster with sufficient resources
- **Talos ISO**: v1.11.5 with required extensions (see cluster-config.yaml)
- **Network**: VLAN configured with static IP range
- **Storage**: Local storage + optional shared storage
- **Tools**: terraform, talosctl, kubectl, helm, kustomize, yq, jq

## 🚀 Getting Started

### Prerequisites

- **Proxmox VE** cluster with sufficient resources
- **Talos ISO** uploaded to Proxmox storage
- **Network** with VLAN and static IP range configured
- **Tools**: terraform, talosctl, kubectl, helm, kustomize, yq, kubeseal

### Quick Start

1. **Configure:** Edit `infra/cluster-config.yaml` with your settings
2. **Deploy:** Run `cd infra && terraform apply`
3. **Bootstrap:** Run `cd ../scripts && ./deploy.sh && ./bootstrap.sh`
4. **Verify:** Check with `kubectl get nodes -o wide`

📖 **Detailed Guide:** See [BOOTSTRAP.md](BOOTSTRAP.md) for complete documentation

### Configuration

Edit `infra/cluster-config.yaml`:

```yaml
cluster:
  name: "my-cluster"
  vip: "192.168.1.100"

nodes:
  "cp-1":
    vm_id: 101
    ip_address: "192.168.1.101"
    proxmox_node: "pve1"
    role: "controlplane"
    # ... more configuration
```

Also create `infra/terraform.tfvars` from `terraform.tfvars.example`.

## 🔧 Operations

### Common Commands

```bash
# Cluster deployment
./scripts/deploy.sh              # Full deployment
./scripts/deploy.sh status       # Check health

# Bootstrap infrastructure
./scripts/bootstrap.sh           # Install all components
./scripts/bootstrap.sh --step 3  # Resume from step 3
./scripts/bootstrap.sh --seal-secrets  # Reseal secrets only

# Access ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Verify cluster
kubectl get nodes -o wide
kubectl get pods -A
kubectl get applications -n argocd
```

📖 **See:** [BOOTSTRAP.md](BOOTSTRAP.md) for detailed operations and troubleshooting

### Managing Secrets

Secrets are managed using sealed-secrets for safe git storage:

```bash
# 1. Edit unsealed secret
vi secrets-un/cert-manager.yaml

# 2. Reseal
./scripts/bootstrap.sh --seal-secrets

# 3. Commit sealed version
git add cluster/security/cert-manager/sealed-secret.yaml
git commit -m "Update secrets"
```

📖 **See:** [BOOTSTRAP.md](BOOTSTRAP.md) for complete secret management workflow

### Talos Operations

```bash
export TALOSCONFIG="infra/talos-config/talosconfig"

# Node management
talosctl --nodes <NODE_IP> version
talosctl --nodes <NODE_IP> reboot
talosctl --nodes <NODE_IP> logs

# Cluster health
talosctl --nodes <CP_IP> health
talosctl --nodes <CP_IP> etcd members
```

📖 **See:** `infra/README.md` for detailed Talos operations

## 🛡️ Security

- **Immutable OS**: Talos Linux with read-only root filesystem
- **No SSH by default**: API-only access via mutual TLS
- **Kernel Hardening**: Optimized kernel parameters (no idle=poll!)
- **RBAC**: Role-based access control enabled
- **Sealed Secrets**: Secrets encrypted with cluster-specific keys
- **Certificate Management**: Automated via cert-manager + Let's Encrypt
- **Network Policies**: Ready for implementation


## 🛠️ Troubleshooting

### Common Issues

**Nodes Not Ready After deploy.sh**
- Expected! Run `./scripts/bootstrap.sh` to install Cilium CNI

**Bootstrap Fails at Step N**
- Resume with: `./scripts/bootstrap.sh --step N`

**Sealed Secrets Not Decrypting**
- Reseal after cluster rebuild: `./scripts/bootstrap.sh --seal-secrets`

**High CPU on Proxmox**
- Check kernel args in `cluster-config.yaml` and remove `idle=poll`

📖 **Detailed Troubleshooting:** See [BOOTSTRAP.md](BOOTSTRAP.md)

### Diagnostics

```bash
# Component logs
kubectl logs -n kube-system -l k8s-app=cilium
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Talos logs
talosctl --nodes <NODE_IP> logs
```

## 📚 Documentation

- **[BOOTSTRAP.md](BOOTSTRAP.md)** - Complete bootstrap guide with troubleshooting
- **[infra/README.md](infra/README.md)** - Infrastructure and Terraform documentation
- **[cluster/README.md](cluster/README.md)** - Cluster manifests and GitOps structure  
- **[scripts/README.md](scripts/README.md)** - Script usage and reference

## 🤝 Contributing

This is a personal homelab project, but feedback and suggestions are welcome!

## 📄 License

This project is provided as-is for educational purposes.
