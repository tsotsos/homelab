# NUT (Network UPS Tools) Server

This directory contains the deployment for NUT server with Prometheus exporter integration.

## Components

- **NUT Server (upsd)**: Monitors UPS devices via SNMP
- **NUT Exporter**: Exports UPS metrics to Prometheus

## Configuration

The configuration is stored in a SealedSecret containing:
- `ups.conf`: UPS device definitions (SNMP endpoints)
- `upsd.conf`: NUT server configuration
- `upsd.users`: User authentication
- `upsmon.conf`: Monitoring configuration

### Monitored UPS Devices

1. **apc-ups-main** (10.0.1.8): Main APC UPS
2. **apc-pdu-net** (10.0.1.9): APC PDU - Networking
3. **apc-pdu-srv** (10.0.1.10): APC PDU - Servers & NAS

## Metrics

The NUT exporter exposes metrics on port 9199 at `/ups_metrics`:
- UPS status and battery information
- Input/output voltage and frequency
- Load percentage
- Runtime remaining

## Updating Configuration

To update the NUT configuration:

```bash
# 1. Edit the unsealed secret
vim secrets-un/nuts-secret.yaml

# 2. Seal the secret
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o name | \
  head -1 | xargs -I {} kubectl get {} -n kube-system -o jsonpath='{.data.tls\.crt}' | \
  base64 -d > /tmp/sealed-secrets.crt
kubeseal --format=yaml --cert=/tmp/sealed-secrets.crt \
  < secrets-un/nuts-secret.yaml > cluster/observability/nut/sealed-secret.yaml
rm /tmp/sealed-secrets.crt

# 3. Commit and push
git add cluster/observability/nut/sealed-secret.yaml
git commit -sm "Update NUT configuration"
git push
```

## Grafana Dashboards

Recommended dashboards:
- Dashboard ID 14371: NUT UPS Metrics

Import via Grafana UI: Configuration → Dashboards → Import → Enter ID 14371
