# Cluster Manifests Directory

This directory contains all Kubernetes applications organized by category, deployed via GitOps with ArgoCD ApplicationSet.

## 📦 Structure

```
cluster/
├── README.md                        # This file
├── main.yaml                        # ArgoCD ApplicationSet (auto-discovers apps)
├── argocd/                          # ArgoCD bootstrap (not managed by itself)
│   ├── kustomization.yaml
│   ├── values.yaml
│   ├── configmap.yaml
│   ├── rbac.yaml
│   └── .argocd-source.yaml
├── network/                         # Network infrastructure
│   ├── cilium/                      # CNI + L7 Ingress Controller
│   │   ├── kustomization.yaml
│   │   ├── values.yaml
│   │   └── .argocd-source.yaml      # Labels: category=network, type=cni
│   ├── kube-vip/                    # LoadBalancer VIP for control plane
│   │   └── .argocd-source.yaml      # Labels: category=network, type=loadbalancer
│   ├── kube-vip-cloud-provider/     # LoadBalancer IP provider
│   │   └── .argocd-source.yaml      # Labels: category=network, type=loadbalancer
│   └── external-dns/                # Automatic DNS record creation
│       ├── sealed-secret.yaml
│       └── .argocd-source.yaml      # Labels: category=network, type=dns
├── security/                        # Security & secrets management
│   ├── sealed-secrets/              # Secret encryption controller
│   │   └── .argocd-source.yaml      # Labels: category=security, type=secrets
│   ├── cert-manager/                # TLS certificate automation
│   │   ├── clusterIssuer.yaml
│   │   ├── sealed-secret.yaml
│   │   └── .argocd-source.yaml      # Labels: category=security, type=certificates
│   └── authentik/                   # SSO & authentication
│       ├── sealed-secret.yaml
│       └── .argocd-source.yaml      # Labels: category=security, type=auth
├── storage/                         # Storage solutions
│   └── longhorn/                    # Distributed block storage
│       └── .argocd-source.yaml      # Labels: category=storage, type=distributed
├── database/                        # Database services
│   └── postgresql/                  # PostgreSQL database
│       ├── sealed-secret.yaml
│       └── .argocd-source.yaml      # Labels: category=database, type=relational
└── observability/                   # Monitoring & logging
    ├── kube-prometheus-stack/       # Prometheus + Grafana + Alertmanager
    │   ├── sealed-secret.yaml
    │   ├── values.yaml
    │   └── .argocd-source.yaml      # Labels: category=observability, type=metrics
    ├── loki/                        # Log aggregation backend
    │   ├── values.yaml
    │   └── .argocd-source.yaml      # Labels: category=observability, type=logs
    └── alloy/                       # Log collection agent (syslog + k8s logs)
        ├── values.yaml
        └── .argocd-source.yaml      # Labels: category=observability, type=logs
```

## 🎯 Purpose

This directory provides all cluster applications organized by category:

1. **Network**: CNI, ingress, LoadBalancer, DNS automation
2. **Security**: Secret management, certificates, authentication
3. **Storage**: Distributed storage solutions
4. **Database**: Database services
5. **Observability**: Monitoring, logging, alerting

Each app has a `.argocd-source.yaml` file with:
- **Labels**: `category`, `type`, `critical` for organization
- **Annotations**: `argocd.argoproj.io/sync-wave` for deployment ordering
- **Kustomize config**: `enable_helm: true` for Helm chart rendering

## 🚀 GitOps with ArgoCD

The `main.yaml` file defines an **ApplicationSet** that auto-discovers apps:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: kng-cluster
spec:
  generators:
    - git:
        directories:
          - path: cluster/*/*  # Matches: cluster/network/cilium, etc.
```

This automatically creates ArgoCD Applications for every app in subdirectories, enabling:
- **Automatic discovery** of new apps (add folder → app deployed)
- **Self-healing** if resources drift from git
- **Namespace auto-creation**
- **Sync waves** for ordered deployment (via `.argocd-source.yaml`)
- **Custom labels** for filtering and organization

## 📋 Category Breakdown

### network/
Network infrastructure deployed first (sync-wave 1-3):
- **cilium**: CNI + L7 ingress (wave 1, critical)
- **kube-vip**: LoadBalancer VIP for HA (wave 2, critical)
- **kube-vip-cloud-provider**: IP allocation (wave 3)
- **external-dns**: Automatic DNS records (wave 3)

### security/
Security components (sync-wave 1-5):
- **sealed-secrets**: Secret encryption controller (wave 1, critical)
- **cert-manager**: TLS certificate automation (wave 2, critical)
- **authentik**: SSO and authentication (wave 5)

### storage/
Storage layer (sync-wave 2):
- **longhorn**: Distributed block storage (wave 2, critical)

### database/
Database services (sync-wave 4):
- **postgresql**: PostgreSQL database (wave 4)

### observability/
Monitoring and logging (sync-wave 4-6):
- **kube-prometheus-stack**: Metrics, Grafana, Alertmanager (wave 4)
- **loki**: Log aggregation backend (wave 5)
- **alloy**: Log collection with syslog support (wave 6)

## 🔧 Usage

### Bootstrap Deployment

```bash
# 1. Deploy Talos cluster
cd scripts/
./deploy.sh

# 2. Bootstrap Cilium + ArgoCD
./bootstrap.sh

# ArgoCD ApplicationSet now auto-deploys all apps!
```

### Manual App Deployment

```bash
# Deploy specific app
kustomize build --enable-helm cluster/network/cilium | kubectl apply -f -

# Deploy ArgoCD
kustomize build --enable-helm cluster/argocd | kubectl apply -f -
```

### Check Deployment Status

```bash
# View all ArgoCD applications
kubectl get applications -n argocd

# Check ApplicationSet
kubectl get applicationsets -n argocd

# View apps by category
kubectl get app -n argocd -l category=network
kubectl get app -n argocd -l category=observability

# Check sync status
kubectl get app -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
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

1. **Create app directory in appropriate category**:
   ```bash
   mkdir -p cluster/network/my-app
   cd cluster/network/my-app
   ```

2. **Create kustomization.yaml with Helm chart**:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   namespace: my-app
   
   helmCharts:
     - name: my-app
       repo: https://charts.example.com
       version: 1.0.0
       releaseName: my-app
       valuesFile: values.yaml
   ```

3. **Create .argocd-source.yaml for labels and sync wave**:
   ```yaml
   labels:
     category: network
     type: custom
   annotations:
     argocd.argoproj.io/sync-wave: "5"
   kustomize:
     enable_helm: true
   ```

4. **Create values.yaml** (optional):
   ```yaml
   # Helm values here
   ```

5. **Commit and push**:
   ```bash
   git add cluster/network/my-app
   git commit -m "Add my-app to network category"
   git push
   ```

6. **ArgoCD automatically discovers and deploys it!**

## 🔍 Sync Wave Order

Applications deploy in order based on sync-wave annotations:

| Wave | Category | Apps | Notes |
|------|----------|------|-------|
| 1 | network, security | cilium, sealed-secrets | Critical infrastructure |
| 2 | network, security, storage | kube-vip, cert-manager, longhorn | Core services |
| 3 | network | kube-vip-cloud-provider, external-dns | Network completion |
| 4 | database, observability | postgresql, kube-prometheus-stack | Data layer |
| 5 | security, observability | authentik, loki | Application services |
| 6 | observability | alloy | Log collection |

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
