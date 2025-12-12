# Homelab Kubernetes Cluster

Production-ready Kubernetes cluster on Talos Linux with GitOps deployment.

## Quick Start

```bash
# 1. Configure
cd infra/ && cp cluster-config.yaml.example cluster-config.yaml
vi cluster-config.yaml  # Set your IPs, MACs, Proxmox nodes

# 2. Deploy VMs
terraform init && terraform apply

# 3. Deploy Kubernetes
cd ../scripts/ && ./deploy.sh

# 4. Install core services
./bootstrap.sh

# 5. Verify
kubectl get nodes
kubectl get applications -n argocd
```

Time: ~20 minutes total. See [infra/README.md](infra/README.md) for details.

## Repository Structure

```
├── infra/              # Terraform + Talos config (see infra/README.md)
├── cluster/            # Kubernetes manifests - GitOps managed (see cluster/README.md)
│   ├── main.yaml       # ArgoCD ApplicationSet
│   ├── network/        # Cilium, kube-vip
│   ├── security/       # Authentik, cert-manager, sealed-secrets
│   ├── storage/        # Longhorn
│   ├── database/       # PostgreSQL
│   ├── observability/  # Prometheus, Loki, Grafana
│   └── home/           # Home Assistant, Zigbee2MQTT, EMQX
├── scripts/            # Deployment automation (see scripts/README.md)
└── secrets-un/         # Unsealed secrets (gitignored)
```

## Core Stack

| Component | Purpose |
|-----------|---------|
| Talos Linux | Immutable OS |
| Kubernetes | Orchestration |
| Cilium | CNI + eBPF networking |
| ArgoCD | GitOps deployment |
| kube-vip | Load balancer IPs |
| Sealed Secrets | Git-safe secrets |
| cert-manager | TLS certificates |
| Longhorn | Distributed storage |
| PostgreSQL | Database |
| Prometheus | Metrics |
| Loki | Logs |
| Grafana | Dashboards |
| Authentik | SSO |

## Architecture

Cluster: 9 VMs across 3 Proxmox hosts (3 control plane + 6 workers)
- Control plane: 4 vCPU, 8GB RAM, 150GB disk each
- Workers: 3-4 vCPU, 8-12GB RAM, 150GB disk each
- Storage nodes: Workers with additional disk for Longhorn
- Zones: 3 physical hosts with node anti-affinity for HA

**Network:**
- VIP: Talos built-in VIP for API endpoint
- LoadBalancer: kube-vip cloud provider
- DNS: external-dns for automatic records

## Prerequisites

- Proxmox VE cluster (3+ nodes recommended)
- Talos Linux ISO v1.11.5+ with extensions
- VLAN with static IP range
- Tools: terraform, talosctl, kubectl, helm, kustomize, yq, kubeseal

### Quick Start

1. **Configure:** Edit `infra/cluster-config.yaml` with your settings
2. **Deploy:** Run `cd infra && terraform apply`
3. **Bootstrap:** Run `cd ../scripts && ./deploy.sh && ./bootstrap.sh`
4. **Verify:** Check with `kubectl get nodes -o wide`

📖 **Detailed Guide:** See [BOOTSTRAP.md](BOOTSTRAP.md) for complete documentation

## Configuration

1. Copy example configs:
```bash
cp infra/cluster-config.yaml.example infra/cluster-config.yaml
cp infra/terraform.tfvars.example infra/terraform.tfvars
```

2. Edit `cluster-config.yaml` with your cluster details (IPs, MACs, Proxmox nodes)

3. Edit `terraform.tfvars` with Proxmox credentials

See [infra/README.md](infra/README.md) for full configuration reference.

## Operations

**Access ArgoCD:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Verify cluster:**
```bash
kubectl get nodes -o wide
kubectl get applications -n argocd
```

**Manage secrets:**

Secrets are managed using sealed-secrets for safe git storage:

```bash
# 1. Edit unsealed secret
vi secrets-un/cert-manager.yaml

# 2. Reseal
./scripts/seal-secrets.sh
git add cluster/ && git commit -m "Update sealed secrets"
```

See [scripts/README.md](scripts/README.md) for secret management details.

## Troubleshooting

**Nodes not ready after deployment:** Install Cilium first via `./scripts/bootstrap.sh`

**Sealed secrets not decrypting:** Reseal after cluster rebuild with `./scripts/seal-secrets.sh`

**ArgoCD sync issues:** Check application status with `kubectl get applications -n argocd`

**Talos diagnostics:**
```bash
export TALOSCONFIG="infra/talos-config/talosconfig"
talosctl --nodes <NODE_IP> health
talosctl --nodes <NODE_IP> logs
```

## Documentation

- [infra/README.md](infra/README.md) - Terraform and Talos configuration
- [cluster/README.md](cluster/README.md) - GitOps structure and applications
- [scripts/README.md](scripts/README.md) - Deployment and bootstrap scripts

## License

GPL-3.0 - See [LICENSE](LICENSE) for details.
