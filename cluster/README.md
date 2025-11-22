# Cluster Manifests Directory

This directory contains cluster-specific Kustomize overlays and configurations that customize the base applications from `apps/` for deployment.

## 📦 Structure

```
cluster/
├── README.md                        # This file
├── main.yaml                        # ArgoCD App-of-Apps (GitOps root)
├── kustomization.yaml               # Root kustomization
├── argocd/                          # ArgoCD customizations
│   ├── .argocd-source.yaml         # ArgoCD-specific directives
│   ├── configmap.yaml               # ConfigMap overlay
│   ├── ingress.yaml                 # Ingress configuration
│   ├── rbac.yaml                    # RBAC configuration
│   └── kustomization.yaml           # Kustomize overlay
├── cert-manager/                    # Cert-Manager customizations
│   ├── clusterIssuer.yaml          # Let's Encrypt issuer
│   ├── sealed-secret.yaml           # Cloudflare API token (sealed)
│   └── kustomization.yaml
├── external-dns/                    # External-DNS customizations
│   ├── sealed-secret.yaml           # UniFi credentials (sealed)
│   └── kustomization.yaml
├── ingress-nginx/                   # Ingress-NGINX customizations
│   └── kustomization.yaml
├── kube-vip-cloud-provider/         # LoadBalancer customizations
│   ├── patch.yaml                   # IP pool configuration
│   └── kustomization.yaml
└── sealed-secrets/                  # Sealed-Secrets customizations
    └── kustomization.yaml
```

## 🎯 Purpose

This directory provides cluster-specific configurations that:

1. **Overlay base apps** from `apps/` with cluster-specific settings
2. **Add secrets** (as sealed secrets, safe for git)
3. **Configure ingress** rules and DNS entries
4. **Set LoadBalancer** IP pools
5. **Define ClusterIssuers** for certificate management
6. **Customize resources** per environment

## 🚀 GitOps with ArgoCD

The `main.yaml` file defines an **App-of-Apps** pattern:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: kng-cluster
spec:
  generators:
    - git:
        directories:
          - path: cluster/*
```

This automatically creates ArgoCD Applications for every subdirectory in `cluster/`, enabling:
- **Automatic sync** when you push to git
- **Self-healing** if resources drift
- **Namespace auto-creation**
- **Centralized management** in ArgoCD UI

## 📋 Directory Breakdown

### argocd/
Customizes ArgoCD itself:
- URL and hostname
- Ingress with TLS
- RBAC policies (optional)
- SSO configuration (commented out)

### cert-manager/
Certificate automation:
- **ClusterIssuer**: Let's Encrypt DNS-01 challenge (Cloudflare)
- **Sealed Secret**: Cloudflare API token
- Namespace: `cert-manager`

### external-dns/
DNS automation:
- **Sealed Secret**: UniFi controller credentials
- **Patch**: Domain filter (`kng.house`)
- Namespace: `external-dns`

### ingress-nginx/
Ingress controller:
- No customizations needed (uses base from `apps/`)
- Namespace: `ingress-nginx`

### kube-vip-cloud-provider/
LoadBalancer IPs:
- **Patch**: IP pool range (configured per environment)
- Provides LoadBalancer IPs for services
- Namespace: `kube-system`

### sealed-secrets/
Secret encryption:
- No customizations needed (uses base from `apps/`)
- Namespace: `kube-system`

## 🔧 Usage

### Apply Manually

```bash
# Apply specific app
kustomize build --enable-helm cluster/argocd | kubectl apply -f -

# Apply all
kustomize build --enable-helm cluster/ | kubectl apply -f -
```

### Deploy via ArgoCD

```bash
# Install ArgoCD first
kustomize build --enable-helm cluster/argocd | kubectl apply -f -

# Apply App-of-Apps
kubectl apply -f cluster/main.yaml

# ArgoCD now manages everything automatically!
```

### Check ArgoCD Status

```bash
kubectl get applications -n argocd
kubectl get applicationsets -n argocd
```

## 🔐 Secrets Management

All secrets in this directory are **sealed** and safe to commit to git:

```bash
cd scripts/

# 1. Edit unsealed secrets (git-ignored)
vi ../secrets-un/cert-manager.yaml
vi ../secrets-un/external-dns.yaml

# 2. Validate format
./sealed-secrets.sh validate

# 3. Seal (encrypt with cluster public key)
./sealed-secrets.sh seal

# 4. Sealed secrets written to cluster/*/sealed-secret.yaml
# 5. Safe to commit!
git add ../cluster/*/sealed-secret.yaml
git commit -m "Update sealed secrets"
git push
```

## 📝 Adding New Applications

1. **Create overlay directory**:
   ```bash
   mkdir cluster/my-app
   ```

2. **Create kustomization.yaml**:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   namespace: my-app
   resources:
     - ../../apps/my-app
   # Add patches, configmaps, secrets here
   ```

3. **Add to root kustomization**:
   ```yaml
   # cluster/kustomization.yaml
   resources:
     - my-app
   ```

4. **ArgoCD auto-detects**:
   - Push to git
   - ArgoCD creates Application automatically
   - App syncs and deploys

## 🎯 ArgoCD Configuration

Each subdirectory can have `.argocd-source.yaml` to control ArgoCD behavior:

```yaml
# cluster/my-app/.argocd-source.yaml
kustomize:
  enable_helm: true  # Required for Helm chart rendering
```

## 📚 References

- [Kustomize Documentation](https://kustomize.io/)
- [ArgoCD App-of-Apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sealed Secrets Workflow](https://github.com/bitnami-labs/sealed-secrets#usage)
