# Scripts Directory

This directory contains deployment and utility scripts for managing the Talos Kubernetes cluster.

## 📜 Scripts

### 🚀 deploy.sh
**Main Talos cluster deployment script**

Deploys Talos Linux to VMs and bootstraps Kubernetes cluster (without CNI).

```bash
./deploy.sh              # Full deployment (apply + bootstrap)
./deploy.sh apply        # Apply Talos configs to VMs (installs Talos)
./deploy.sh bootstrap    # Bootstrap Kubernetes cluster
./deploy.sh status       # Check cluster status
```

**What it does:**
1. Uses Terraform-generated configs from `infra/talos-config/`
2. Applies machine configs to all nodes with `--insecure` flag
3. Waits for nodes to be ready (2-5 minutes per node)
4. Bootstraps Kubernetes on first control plane (10.0.2.101)
5. Retrieves kubeconfig to `infra/talos-config/kubeconfig`

**After deployment:** Nodes will be **NotReady** until CNI is installed (run `bootstrap.sh`)

---

### 🎯 bootstrap.sh
**Comprehensive Kubernetes bootstrap script**

Installs all core infrastructure components and seals secrets automatically.

```bash
./bootstrap.sh                    # Run full bootstrap (or resume)
./bootstrap.sh --step <N>         # Resume from specific step
./bootstrap.sh --seal-secrets     # Only seal secrets
./bootstrap.sh --reset            # Clear state and start fresh
./bootstrap.sh --help             # Show help
```

**Bootstrap Steps:**

0. **Apply Node Labels** - Labels nodes based on cluster-config.yaml
1. **Cilium CNI** - Network plugin with eBPF optimization
2. **Kube-VIP** - Load balancer for services
3. **Sealed Secrets** - Encrypts and seals all secrets from secrets-un/
4. **External-DNS** - Automatic DNS management
5. **Cert-Manager** - TLS certificate automation
6. **Longhorn** - Distributed storage system
7. **ArgoCD** - GitOps continuous delivery

**Features:**
- ✅ Automatic secret sealing with namespace detection
- ✅ State management for resumable bootstraps
- ✅ Helm chart cleanup after installation
- ✅ Removes problematic creationTimestamp fields
- ✅ Displays ArgoCD admin password on completion
**Secret Management:**
The bootstrap script automatically finds and seals all secrets in `secrets-un/` directory:
- Detects namespace from secret YAML
- Finds matching directory in cluster/
- Seals using kubeseal (direct cluster access)
- Removes problematic creationTimestamp fields
- Places sealed-secret.yaml in correct app folder

**Resuming Failed Bootstrap:**
If bootstrap fails at any step:
```bash
./bootstrap.sh --step 3  # Resume from step 3 (sealed-secrets)
```

Or let it auto-resume:
```bash
./bootstrap.sh  # Prompts to resume from last completed step
```

**Resealing Secrets Later:**
After cluster is running with sealed-secrets controller:
```bash
./bootstrap.sh --seal-secrets  # Only reseal all secrets
```

**After bootstrap:**
- Cluster is fully functional with all core components
- ArgoCD ready to deploy applications via GitOps
- All secrets encrypted and safe for git storage
- ArgoCD admin password displayed for UI access

---

## 🔧 Usage Examples

### Fresh Deployment

```bash
# 1. Deploy infrastructure (Terraform)
cd ../infra/
terraform apply

# 2. Deploy Talos cluster
cd ../scripts/
./deploy.sh

# 3. Bootstrap services
./bootstrap.sh

# 4. Check status
./deploy.sh status
kubectl get nodes -o wide
```

### Redeploy Cluster

```bash
# Destroy and recreate
cd ../infra/
terraform destroy
terraform apply

cd ../scripts/
./deploy.sh
./bootstrap.sh
```

### Update Secrets

```bash
# Edit unsealed secrets
vi ../secrets-un/cert-manager.yaml

# Validate and seal
./sealed-secrets.sh validate
./sealed-secrets.sh seal

# Commit sealed secrets
git add ../cluster/cert-manager/sealed-secret.yaml
git commit -m "Update Cloudflare API token"
git push

# ArgoCD auto-syncs the sealed secret!
```

### Troubleshooting

```bash
# Check cluster status
./deploy.sh status

# View Talos logs
export TALOSCONFIG="../infra/talos-config/talosconfig"
talosctl --nodes 10.0.2.101 logs

# View Kubernetes events
export KUBECONFIG="../infra/talos-config/kubeconfig"
kubectl get events -A --sort-by='.lastTimestamp'

# Check ArgoCD apps
kubectl get applications -n argocd
```

---

## 📋 Script Dependencies

### Required Environment
- `talosctl` - Talos CLI
- `kubectl` - Kubernetes CLI
- `helm` - Helm package manager
- `kustomize` - Kustomize CLI
- `yq` - YAML processor
- `jq` - JSON processor

### File Dependencies
- `../infra/cluster-config.yaml` - Cluster configuration
- `../infra/talos-config/` - Terraform-generated configs
- `../infra/talos-config/talosconfig` - Talos client config
- `../infra/talos-config/kubeconfig` - Kubernetes client config
- `../secrets-un/` - Unsealed secrets (git-ignored)
- `../cluster/` - Cluster manifests

---

## 🛡️ Security Notes

### Secrets Management

**NEVER commit unsealed secrets to git!**

- ✅ **Safe**: `cluster/*/sealed-secret.yaml` (encrypted)
- ❌ **UNSAFE**: `secrets-un/*.yaml` (plaintext, git-ignored)
- ❌ **UNSAFE**: `secrets.env` (credentials, git-ignored)

### Certificate Management

**NEVER regenerate Talos certificates manually!**

- Always use Terraform-generated configs
- Located in: `infra/talos-config/`
- Regenerate via: `terraform apply -target=local_file.talosconfig`

### Git Ignore

Ensure `.gitignore` excludes:
```
talos-config/
*.talosconfig
secrets-un/
secrets.env
*.key
*.pem
```

---

## 📚 References

- [Talos Linux Documentation](https://www.talos.dev/v1.11/)
- [Cilium Documentation](https://docs.cilium.io/en/stable/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
