# Deployment Scripts

**License:** GPL-3.0 - See [LICENSE](../LICENSE)

## deploy.sh

Deploys Talos Linux and bootstraps Kubernetes cluster (without CNI).

```bash
./deploy.sh              # Full deployment
./deploy.sh apply        # Apply Talos configs only
./deploy.sh bootstrap    # Bootstrap Kubernetes only
./deploy.sh status       # Check cluster status
```

Process:
1. Applies machine configs from `infra/talos-config/`
2. Waits for nodes to be ready
3. Bootstraps Kubernetes on first control plane
4. Saves kubeconfig to `infra/talos-config/kubeconfig`

Nodes will be NotReady until CNI is installed (run `bootstrap.sh`).

## bootstrap.sh

Installs core infrastructure and seals secrets.

```bash
./bootstrap.sh                    # Full bootstrap or resume
./bootstrap.sh --step <N>         # Resume from step N
./bootstrap.sh --seal-secrets     # Seal secrets only
./bootstrap.sh --reset            # Clear state
```

**Steps:**
0. Apply node labels
1. Cilium CNI
2. kube-vip
3. Sealed Secrets (auto-seals from secrets-un/)
4. external-dns
5. cert-manager
6. Longhorn
7. ArgoCD

**Secret sealing:**
- Finds secrets in `secrets-un/`
- Detects namespace
- Seals with kubeseal
- Places sealed-secret.yaml in correct cluster/ directory
- Removes problematic creationTimestamp fields

**Resuming:** Script tracks state and can resume from any step if interrupted.
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

## seal-secrets.sh

Validates and seals secrets from `secrets-un/`.

```bash
./seal-secrets.sh            # Interactive mode
./seal-secrets.sh validate   # Check unsealed secrets
./seal-secrets.sh seal       # Seal all secrets
```

Places sealed secrets in correct cluster/ directories based on namespace.

## label-nodes.sh

Applies node labels from cluster-config.yaml. Called automatically by bootstrap.sh.

## Dependencies

Required tools: `talosctl`, `kubectl`, `helm`, `kustomize`, `yq`, `jq`, `kubeseal`

Required files:
- `infra/cluster-config.yaml`
- `infra/talos-config/talosconfig`
- `infra/talos-config/kubeconfig`

## Security

**Never commit to git:**
- `secrets-un/*.yaml` (plaintext secrets)
- `secrets.env` (credentials)
- `infra/talos-config/*` (certificates and configs)

**Safe to commit:**
- `cluster/*/sealed-secret.yaml` (encrypted)
