# Applications Directory

This directory contains Helm chart definitions and Kustomize configurations for all applications deployed to the cluster.

## 📦 Structure

Each application directory contains:
- `kustomization.yaml` - Kustomize configuration with Helm chart references
- `ns.yaml` - Namespace definition (if needed)
- `values.yaml` - Helm chart values overrides
- `charts/` - Downloaded Helm charts (ignored in git)

## 🎯 Applications

### Core Infrastructure

- **argocd/** - GitOps continuous deployment controller
  - Chart: `argo-cd` v8.2.5
  - Namespace: `argocd`
  - Purpose: Manages all other applications via GitOps

- **sealed-secrets/** - Bitnami Sealed Secrets controller
  - Chart: `sealed-secrets` v2.17.9
  - Namespace: `kube-system`
  - Purpose: Encrypts Kubernetes secrets for safe git storage

### Networking

- **ingress-nginx/** - NGINX Ingress Controller
  - Chart: `ingress-nginx` v4.13.0
  - Namespace: `ingress-nginx`
  - Purpose: HTTP/HTTPS traffic routing and load balancing

- **external-dns/** - External DNS automation
  - Chart: `external-dns` (latest)
  - Namespace: `external-dns`
  - Purpose: Automatically manages DNS records (UniFi integration)

- **kube-vip-cloud-provider/** - LoadBalancer IP provider
  - Chart: `kube-vip-cloud-provider` (latest)
  - Namespace: `kube-system`
  - Purpose: Provides LoadBalancer IPs from pool (10.0.2.75-99)

### Security & Certificates

- **cert-manager/** - Certificate management
  - Chart: `cert-manager` (latest)
  - Namespace: `cert-manager`
  - Purpose: Automated TLS certificate management (Let's Encrypt)

### Storage

- **longhorn/** - Distributed block storage
  - Chart: `longhorn` (latest)
  - Namespace: `longhorn-system`
  - Purpose: Persistent volumes across worker nodes

### Management

- **rancher/** - Kubernetes management platform
  - Chart: `rancher` (latest)
  - Namespace: `cattle-system`
  - Purpose: Multi-cluster management and monitoring

### Utilities

- **netboot.xyz/** - Network boot server
  - Direct YAML deployment
  - Namespace: `default`
  - Purpose: PXE boot services

## 🔧 Usage

Applications are **not applied directly** from this directory. They are managed through:

1. **Cluster Overlays**: See `cluster/` directory for cluster-specific configurations
2. **ArgoCD**: Automatically syncs from git via App-of-Apps pattern
3. **Kustomize**: Helm charts are rendered via kustomize `--enable-helm`

### Installing an Application Manually

```bash
# Build and apply with Helm rendering
kustomize build --enable-helm apps/argocd | kubectl apply -f -

# Or use cluster overlay
kustomize build --enable-helm cluster/argocd | kubectl apply -f -
```

### Managing Helm Charts

```bash
# Charts are downloaded automatically by kustomize/ArgoCD
# To clean up downloaded charts:
find apps/ -name "charts" -type d -exec rm -rf {} +
```

## 📋 Adding New Applications

1. Create application directory: `apps/my-app/`
2. Add `kustomization.yaml` with Helm chart reference
3. Add `values.yaml` with configuration overrides
4. Create cluster overlay in `cluster/my-app/`
5. Add to `cluster/kustomization.yaml` resources
6. ArgoCD will auto-detect and deploy

Example `apps/my-app/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: my-app
helmCharts:
  - name: my-app
    repo: https://charts.example.com
    version: 1.0.0
    releaseName: my-app
    namespace: my-app
    valuesFile: values.yaml
    includeCRDs: true
```

## 🔐 Secrets Management

Never commit unencrypted secrets! Use sealed-secrets:

```bash
# Unsealed secrets go in secrets-un/ (git-ignored)
# Sealed secrets go in cluster/*/sealed-secret.yaml (safe to commit)

cd scripts/
./sealed-secrets.sh validate  # Check format
./sealed-secrets.sh seal      # Encrypt
```

## 📚 References

- [Kustomize Helm Integration](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/chart.md)
- [ArgoCD App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
