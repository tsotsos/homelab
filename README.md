# 🏠 Homelab Infrastructure

Enterprise-grade Kubernetes homelab with Talos Linux, GitOps, and comprehensive application stack.

## 🚀 Quick Start

### Infrastructure Deployment

For complete cluster deployment and management:

📖 **[Infrastructure Documentation](./infra/README.md)** - Complete setup guide with Terraform + Talos

```bash
# Deploy Talos Kubernetes cluster
cd infra/
./deploy-talos-cluster.sh

# Check cluster status
./deploy-talos-cluster.sh diagnostics
```

## 📁 Repository Structure

```
homelab/
├── 📖 README.md                    # This overview
├── 🏗️ infra/                       # Infrastructure (Terraform + Talos)
│   ├── README.md                   # Complete deployment guide
│   ├── deploy-talos-cluster.sh     # Unified deployment script
│   ├── cluster-config.yaml         # Cluster configuration
│   ├── main.tf                     # Infrastructure definition
│   └── talos-config/              # Generated configs
├── 📦 apps/                        # Application definitions
│   ├── argocd/                    # GitOps controller
│   ├── cert-manager/              # Certificate management
│   ├── ingress-nginx/             # Ingress controller
│   ├── longhorn/                  # Storage solution
│   └── rancher/                   # Kubernetes management
├── 🎯 clusters/                    # Cluster-specific configs
│   └── management/                # Management cluster
└── 📜 scripts/                     # Utility scripts
```

## ✨ Features

- **🏗️ Infrastructure as Code**: Terraform-managed Proxmox VMs
- **⚡ Fast Deployment**: Parallel processing (15-20 mins total)
- **🔧 Per-VM Customization**: Individual resource allocation
- **🌐 Multi-Architecture**: AMD64 + ARM64 support
- **🛡️ Security First**: Sealed secrets, RBAC, policies
- **📊 GitOps Ready**: ArgoCD-managed applications
- **🏥 Self-Healing**: Automated monitoring and recovery

## 🎯 Core Stack

| Component | Purpose | Status |
|-----------|---------|--------|
| **Talos Linux** | Immutable OS | ✅ |
| **Kubernetes** | Container orchestration | ✅ |
| **ArgoCD** | GitOps deployment | ✅ |
| **Cert-Manager** | TLS certificates | ✅ |
| **Ingress-NGINX** | Load balancing | ✅ |
| **Longhorn** | Distributed storage | ✅ |
| **Rancher** | Cluster management | ✅ |
| **Sealed-Secrets** | Secret management | ✅ |

## 📋 Prerequisites

- **3 Proxmox VE nodes** in cluster
- **Talos Linux template** configured
- **Network bridge** (`vmbr1`) setup
- **Storage pools** (`local-lvm`, `zfs-pool`)

## 🚀 Getting Started

1. **Setup Infrastructure**
   ```bash
   cd infra/
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your settings
   ```

2. **Deploy Cluster**
   ```bash
   ./deploy-talos-cluster.sh
   ```

3. **Verify Deployment**
   ```bash
   ./deploy-talos-cluster.sh diagnostics
   kubectl get nodes -o wide
   ```

4. **Access Applications**
   ```bash
   # Setup port forwarding or ingress
   kubectl port-forward -n argocd svc/argocd-server 8080:443
   ```

## 🔧 Operations

### Daily Operations
```bash
# Cluster status
cd infra/ && ./deploy-talos-cluster.sh status

# Health check
./deploy-talos-cluster.sh diagnostics

# View logs
./deploy-talos-cluster.sh logs
```

### Scaling
```bash
# Add external node
./deploy-talos-cluster.sh add-external-node "worker-ext" "192.168.1.100"

# Scale Proxmox workers
# Edit terraform.tfvars: worker_count_per_proxmox_node = 3
terraform apply
```

## 🛡️ Security

- **Immutable OS** with Talos Linux
- **RBAC** enabled by default
- **Pod Security Standards** enforced
- **Network Policies** ready
- **Certificate Management** automated
- **Secret Encryption** via sealed-secrets
- **Air-gapped** deployment support

## 📊 Monitoring

- **Built-in Diagnostics**: `./deploy-talos-cluster.sh diagnostics`
- **Kubernetes Events**: `kubectl get events -A`
- **Node Status**: `talosctl health`
- **Application Health**: ArgoCD dashboard

## 🎯 Use Cases

- **Development Environment**: Rapid deployment/teardown
- **Production Homelab**: High availability setup
- **Learning Platform**: Kubernetes + GitOps education
- **Testing Ground**: New applications and configurations
- **Edge Computing**: Multi-location deployments

## 📚 Documentation

- **[Infrastructure Guide](./infra/README.md)** - Complete setup and operations
- **Application Configs** - Individual app documentation in `apps/`
- **Scripts Reference** - Utility script documentation in `scripts/`

## 🆘 Support

### Quick Diagnostics
```bash
cd infra/
./deploy-talos-cluster.sh diagnostics  # Comprehensive health check
./deploy-talos-cluster.sh help         # See all commands
```

### Troubleshooting
- Check infrastructure documentation: `./infra/README.md`
- View deployment logs: `./deploy-talos-cluster.sh logs`
- Verify cluster health: `kubectl get nodes -o wide`

---

**🎉 Ready to deploy your enterprise-grade homelab!**

Start with the [Infrastructure Documentation](./infra/README.md) for complete setup instructions.