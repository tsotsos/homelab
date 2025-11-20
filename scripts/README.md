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
**Kubernetes bootstrap script - installs CNI and GitOps**

Installs Cilium CNI and ArgoCD on a freshly bootstrapped cluster.

```bash
./bootstrap.sh           # Full bootstrap (Cilium + ArgoCD)
./bootstrap.sh cilium    # Install only Cilium CNI
./bootstrap.sh argocd    # Install only ArgoCD (requires Cilium)
```

**What it installs:**

1. **Cilium CNI (1.18.4)**
   - Uses Talos VIP (10.0.2.100) for API endpoint
   - Talos-specific security contexts
   - eBPF optimizations
   - Nodes become **Ready** after installation

2. **ArgoCD (8.2.5)**
   - GitOps controller
   - Deployed from `cluster/argocd/`
   - Auto-discovers apps in `cluster/` directory

3. **App-of-Apps**
   - Applies `cluster/main.yaml`
   - ArgoCD automatically deploys all apps from git

4. **Node Labels**
   - Applies `node-role.kubernetes.io/worker` labels
   - (Cannot be set via Talos machine config)

**After bootstrap:**
- Cluster is fully functional
- ArgoCD manages all applications via GitOps
- Display admin password for ArgoCD UI access

---

### 🏷️ label-nodes.sh
**Apply worker node role labels**

Applies `node-role.kubernetes.io/worker` labels to worker nodes.

```bash
./label-nodes.sh
```

**Why needed:** Protected Kubernetes labels (node-role.kubernetes.io/*) cannot be set via Talos machine configuration and must be applied post-bootstrap via kubectl.

**Labels applied:**
- `node-role.kubernetes.io/worker=worker` on all 6 worker nodes

**Called automatically by:** `bootstrap.sh`

---

### 🔐 sealed-secrets.sh
**Manage sealed secrets for safe git storage**

Encrypts Kubernetes secrets using cluster-specific public key, enabling safe commit to git.

```bash
./sealed-secrets.sh all       # Install controller + seal all secrets
./sealed-secrets.sh install   # Install sealed-secrets controller only
./sealed-secrets.sh validate  # Validate unsealed secret format
./sealed-secrets.sh seal      # Encrypt unsealed secrets
./sealed-secrets.sh unseal    # Decrypt sealed secrets (requires cluster access)
```

**Workflow:**

1. **Edit unsealed secrets** (git-ignored):
   ```bash
   vi ../secrets-un/cert-manager.yaml
   vi ../secrets-un/external-dns.yaml
   ```

2. **Validate format** (checks namespace/name):
   ```bash
   ./sealed-secrets.sh validate
   ```

3. **Seal secrets** (encrypts with cluster public key):
   ```bash
   ./sealed-secrets.sh seal
   ```
   - Reads from: `secrets-un/*.yaml` (git-ignored)
   - Writes to: `cluster/*/sealed-secret.yaml` (safe to commit)

4. **Commit sealed secrets**:
   ```bash
   git add ../cluster/*/sealed-secret.yaml
   git commit -m "Update sealed secrets"
   git push
   ```

**Managed secrets:**
- `cert-manager.yaml` → `cluster/cert-manager/sealed-secret.yaml`
- `external-dns.yaml` → `cluster/external-dns/sealed-secret.yaml`

**Validation checks:**
- Correct namespace (cert-manager, external-dns)
- Correct secret name
- Valid YAML format

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
