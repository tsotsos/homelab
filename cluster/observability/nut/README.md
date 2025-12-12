# NUT (Network UPS Tools)

**License:** GPL-3.0 - See [LICENSE](../../../LICENSE)

Monitors UPS devices via SNMP and exports metrics to Prometheus.

## Components

- NUT Server (upsd): Monitors UPS via SNMP
- NUT Exporter: Prometheus metrics on port 9199

## Configuration

Configuration stored in SealedSecret:
- `ups.conf`: UPS device definitions (SNMP endpoints)
- `upsd.conf`: Server configuration
- `upsd.users`: Authentication
- `upsmon.conf`: Monitoring settings

## Metrics

Exposed at `/ups_metrics`:
- UPS status and battery info
- Input/output voltage and frequency
- Load percentage
- Runtime remaining

## Updating

```bash
# Edit unsealed secret
vim secrets-un/nut-secret.yaml

# Seal and commit
cd scripts && ./seal-secrets.sh
git add ../cluster/observability/nut/sealed-secret.yaml
git commit -m "Update NUT configuration"
git push
```

## Grafana Dashboards

Recommended dashboards:
- Dashboard ID 14371: NUT UPS Metrics

Import via Grafana UI: Configuration → Dashboards → Import → Enter ID 14371
