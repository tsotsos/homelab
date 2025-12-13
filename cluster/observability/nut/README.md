# NUT (Network UPS Tools)

**License:** GPL-3.0 - See [LICENSE](../../../LICENSE)

Monitors UPS and PDU devices via SNMP with web UI and Prometheus metrics.

## Components

- **NUT Server (upsd)**: Monitors UPS and PDUs via SNMP
- **NUT Exporter**: Prometheus metrics on port 9199
- **PeaNUT**: Web UI for monitoring and management on port 8080

## Devices

- **ups1**: APC Smart-UPS SRT 5000 (10.0.1.8) - Main UPS with full metrics
- **pdu1**: APC AP7920 PDU (10.0.1.9) - 8 switchable outlets, rack-top
- **pdu2**: APC AP7920 PDU (10.0.1.10) - 8 switchable outlets, rack-bottom

## Configuration

Configuration embedded in deployment manifest:
- `ups.conf`: UPS/PDU device definitions (SNMP endpoints with apc_pdu MIB)
- `upsd.conf`: Server configuration
- `upsd.users`: Authentication credentials
- `upsmon.conf`: Monitoring settings

## Metrics

Prometheus metrics exposed at `/ups_metrics?ups=<device>`:
- Battery: charge, runtime, voltage, date
- Input: voltage, frequency, transfer thresholds
- Output: voltage, current, frequency
- UPS: load, power, realpower, temperature, status
- Device: model, serial, firmware

## Web Interface

PeaNUT accessible at `https://peanut.kng.house` (Authentik SSO):
- Real-time monitoring of all devices
- Execute UPS commands
- View device status and history
- API access at `/api/v1/*`

## Updating Configuration

Configuration is inline in `deployment.yaml`. To update:

```bash
# Edit deployment
vim cluster/observability/nut/deployment.yaml

# Apply changes
kubectl apply -f cluster/observability/nut/deployment.yaml
kubectl rollout restart deployment/nut-server -n monitoring
```

## Grafana Dashboards

Recommended dashboards:
- Dashboard ID 14371: NUT UPS Metrics
- Custom dashboard for real power and kWh tracking

Import via Grafana UI: Configuration → Dashboards → Import

## Authentik Configuration

PeaNUT is protected by Authentik forward auth:
1. Create Provider: Proxy Provider, Forward auth (single application)
2. Create Application: Name "PeaNUT", slug "peanut"
3. Assign to embedded outpost
4. Access at `https://peanut.kng.house`
