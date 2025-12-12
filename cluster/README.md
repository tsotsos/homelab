# Cluster Manifests

**License:** GPL-3.0 - See [LICENSE](../LICENSE)

GitOps-managed Kubernetes applications deployed via ArgoCD ApplicationSet.

## Structure

```
cluster/
├── main.yaml           # ArgoCD ApplicationSet (auto-discovers apps)
├── argocd/             # ArgoCD bootstrap
├── network/            # Cilium, kube-vip, external-dns
├── security/           # sealed-secrets, cert-manager, authentik
├── storage/            # Longhorn
├── database/           # PostgreSQL
├── observability/      # Prometheus, Loki, Grafana, Vector
└── home/               # Home Assistant, Zigbee2MQTT, EMQX
```

## GitOps Pattern

`main.yaml` defines an ApplicationSet that auto-discovers apps:

```yaml
generators:
  - git:
      directories:
        - path: cluster/*/*
```

Each app directory contains:
- `kustomization.yaml` - Kustomize manifest
- `values.yaml` - Helm values (if using Helm chart)
- `sealed-secret.yaml` - Encrypted secrets
- `.argocd-source.yaml` - ArgoCD metadata (labels, sync wave)

Adding a new app: Create directory under category → ArgoCD auto-deploys.

## Deployment Order

Applications deploy in waves via `argocd.argoproj.io/sync-wave` annotation:

1. **Wave 1**: Cilium (CNI required first)
2. **Wave 2**: kube-vip, sealed-secrets
3. **Wave 3**: cert-manager, external-dns
4. **Wave 4**: Storage, databases
5. **Wave 5**: Applications

## Categories

**network/** - Cilium CNI, kube-vip load balancer, external-dns
**security/** - Sealed secrets, cert-manager, Authentik SSO
**storage/** - Longhorn distributed storage
**database/** - PostgreSQL with read replicas
**observability/** - Prometheus, Grafana, Loki, Vector
**home/** - Home automation stack
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

## Secrets Management

All secrets are sealed and safe to commit:

```bash
# Edit unsealed secrets (gitignored)
vi ../secrets-un/cert-manager.yaml

# Seal with cluster key
cd ../scripts && ./seal-secrets.sh

# Commit sealed secrets
git add ../cluster/*/sealed-secret.yaml
git commit -m "Update secrets"
```

## Adding Applications

1. Create directory: `mkdir -p cluster/category/app-name`
2. Add `kustomization.yaml` with Helm chart reference
3. Add `values.yaml` (if needed)
4. Add `.argocd-source.yaml` for sync wave and labels
5. Commit and push - ArgoCD auto-deploys

Example `.argocd-source.yaml`:
```yaml
labels:
  category: network
annotations:
  argocd.argoproj.io/sync-wave: "3"
kustomize:
  enable_helm: true
```

## Management

```bash
# View applications
kubectl get applications -n argocd

# Filter by category
kubectl get app -n argocd -l category=network

# Check sync status
kubectl get app -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```
