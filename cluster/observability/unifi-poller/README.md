# UniFi Poller

UniFi Poller collects metrics from UniFi Controller and exports them to Prometheus for monitoring.

## Overview

- **Application**: UniFi Poller v2.16.0
- **Namespace**: `monitoring`
- **Helm Chart**: [unpoller/unpoller](https://github.com/unpoller/helm-chart) v2.11.2
- **Metrics Port**: 9130

## Features

- Collects all UniFi Controller, Site, Device & Client data
- Exports metrics to Prometheus
- Optional log export to Loki
- Grafana dashboards available at [Grafana Dashboards](https://grafana.com/grafana/dashboards/?search=unifi-poller)

## Configuration

### UniFi Controller Connection

The application connects to your UniFi Controller using credentials stored in a sealed secret:

- **Controller URL**: `https://unifi.kng.house`
- **Authentication**: Username/password from `unifi-poller-secrets`
- **SSL Verification**: Disabled (adjust if using valid certificates)

### Metrics Collection

- **Prometheus**: Enabled (default)
- **Interval**: 2 minutes
- **Namespace**: `unifipoller`
- **ServiceMonitor**: Auto-configured for Prometheus Operator

### Data Collection

Enabled:
- Sites data
- DPI (Deep Packet Inspection) data

Disabled (can be enabled in values.yaml):
- IDS events
- Alarms
- Anomalies
- Events

## Prerequisites

1. **UniFi Controller**: Must be accessible from the cluster
2. **Service Account**: Create a read-only user in UniFi Controller
   - Navigate to Settings → Admins
   - Add new admin with "Read Only" role
   - Use these credentials in the secret

## Deployment

### 1. Create Unsealed Secret

Edit `secrets-un/unifi-poller.yaml`:

```yaml
stringData:
  unifi-user: "your-unifi-readonly-user"
  unifi-password: "your-unifi-password"
```

### 2. Seal the Secret

```bash
cd /Users/george/Projects/homelab
./scripts/sealed-secrets.sh secrets-un/unifi-poller.yaml cluster/observability/unifi-poller/sealed-secret.yaml
```

### 3. Deploy via ArgoCD

The application will be automatically picked up by the ArgoCD ApplicationSet once committed to git.

## Grafana Dashboards

Import pre-built dashboards from Grafana:

1. Navigate to Grafana → Dashboards → Import
2. Use these dashboard IDs:
   - **11315**: UniFi Poller: Client Insights - Prometheus
   - **11311**: UniFi Poller: Network Sites - Prometheus
   - **11314**: UniFi Poller: USW Insights - Prometheus
   - **11312**: UniFi Poller: UAP Insights - Prometheus
   - **11313**: UniFi Poller: USG Insights - Prometheus

Or browse all available dashboards: https://grafana.com/grafana/dashboards/?search=unifi-poller

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=unpoller
```

### View Logs

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=unpoller --tail=100
```

### Test Metrics Endpoint

```bash
kubectl port-forward -n monitoring svc/unifi-poller 9130:9130
curl http://localhost:9130/metrics
```

### Common Issues

1. **Connection Refused**: Verify UniFi Controller URL is accessible from the cluster
2. **Authentication Failed**: Double-check credentials and user permissions
3. **SSL Errors**: If using self-signed certs, ensure `UP_UNIFI_DEFAULT_VERIFY_SSL` is set to `false`

## Resources

- [Official Documentation](https://unpoller.com/)
- [GitHub Repository](https://github.com/unpoller/unpoller)
- [Helm Chart](https://github.com/unpoller/helm-chart)
- [Configuration Reference](https://unpoller.com/docs/install/configuration)
