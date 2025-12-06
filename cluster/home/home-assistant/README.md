# Home Assistant Deployment

Complete Home Assistant deployment with PostgreSQL database, InfluxDB metrics storage, automated backups, and disaster recovery capabilities.

## Architecture

### Components

1. **Home Assistant Core**: Latest stable version running in Kubernetes
2. **PostgreSQL Database**: Primary data storage with dedicated database and user
3. **InfluxDB Bucket**: Time-series metrics storage for long-term history
4. **Longhorn Storage**: 
   - 20Gi for configuration (`/config`)
   - 50Gi for backups (`/config/backups`)
5. **Automated Backups**: Daily CronJob at 3 AM keeping last 7 backups
6. **Ingress**: TLS-enabled access via `homeassistant.kng.house`

### Storage Layout

```
/config (20Gi PVC - home-assistant-home-assistant)
├── configuration.yaml
├── automations.yaml
├── scripts.yaml
└── ... (Home Assistant config files)

/config/backups (50Gi PVC - homeassistant-backups)
├── backup-20241206-030000.tar.gz
├── backup-20241205-030000.tar.gz
└── ... (automated backups, 7 days retention)
```

## Initial Setup

### 1. Deploy PostgreSQL Database

The database initialization job (`db-init.yaml`) creates:
- Database: `homeassistant`
- User: `homeassistant`
- Grants all privileges on the database

Monitor initialization:
```bash
kubectl logs -n postgresql job/homeassistant-db-init
```

### 2. Deploy InfluxDB Bucket

The InfluxDB initialization job (`influxdb-init.yaml`) creates:
- Bucket: `homeassistant` (infinite retention)
- Token: With read/write permissions

Monitor initialization:
```bash
kubectl logs -n influxdb job/homeassistant-influxdb-init
```

### 3. Deploy Home Assistant

ArgoCD will automatically deploy Home Assistant once the configuration is committed.

Check deployment status:
```bash
kubectl get pods -n home-assistant
kubectl logs -n home-assistant deployment/home-assistant
```

## Configuration

### Database Connection

Home Assistant is pre-configured with PostgreSQL recorder:

```yaml
# Automatically configured via POSTGRES_URL environment variable
recorder:
  db_url: !env_var POSTGRES_URL
  purge_keep_days: 30
  commit_interval: 1
```

### InfluxDB Integration

Add to Home Assistant `configuration.yaml`:

```yaml
influxdb:
  api_version: 2
  host: influxdb-influxdb2.influxdb.svc.cluster.local
  port: 8086
  token: !secret influxdb_token
  organization: influxdata
  bucket: homeassistant
  tags:
    source: homeassistant
  include:
    domains:
      - sensor
      - binary_sensor
      - climate
```

Add to `secrets.yaml` (Home Assistant will read from mounted secret):
```yaml
influxdb_token: <token from /secrets/influxdb-token>
```

## Backup & Recovery

### Automated Backups

- **Schedule**: Daily at 3:00 AM UTC
- **Retention**: Last 7 backups
- **Location**: `/config/backups` on separate PVC
- **Format**: Home Assistant native backup format (`.tar.gz`)

Manual backup:
```bash
kubectl exec -n home-assistant deployment/home-assistant -- ha backups new --name manual-backup
```

List backups:
```bash
kubectl exec -n home-assistant deployment/home-assistant -- ha backups list
```

### Disaster Recovery Procedure

#### Scenario 1: Configuration Corruption

1. List available backups:
```bash
kubectl exec -n home-assistant deployment/home-assistant -- ha backups list
```

2. Restore from backup:
```bash
kubectl exec -n home-assistant deployment/home-assistant -- ha backups restore <backup-slug>
```

3. Restart Home Assistant:
```bash
kubectl rollout restart deployment/home-assistant -n home-assistant
```

#### Scenario 2: Complete Data Loss

1. **Restore PostgreSQL Database**:
```bash
# If you have PostgreSQL backups
kubectl exec -n postgresql postgresql-primary-0 -- \
  psql -U postgres -c "DROP DATABASE IF EXISTS homeassistant;"
kubectl exec -n postgresql postgresql-primary-0 -- \
  psql -U postgres -c "CREATE DATABASE homeassistant OWNER homeassistant;"
kubectl exec -n postgresql postgresql-primary-0 -- \
  psql -U homeassistant -d homeassistant < /path/to/backup.sql
```

2. **Restore Home Assistant Configuration**:
```bash
# Access the backup PVC
kubectl run -n home-assistant backup-restore --rm -it \
  --image=alpine:latest \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "backup-restore",
      "image": "alpine:latest",
      "command": ["/bin/sh"],
      "stdin": true,
      "tty": true,
      "volumeMounts": [{
        "name": "backups",
        "mountPath": "/backups"
      }]
    }],
    "volumes": [{
      "name": "backups",
      "persistentVolumeClaim": {
        "claimName": "homeassistant-backups"
      }
    }]
  }
}' -- /bin/sh

# Inside the pod, list and copy backup
ls -lh /backups
```

3. **Restore via Home Assistant UI**:
   - Access https://homeassistant.kng.house
   - Go to Settings → System → Backups
   - Select backup and click "Restore"

#### Scenario 3: Longhorn Volume Snapshot Recovery

Longhorn provides volume-level snapshots:

1. **Create manual snapshot**:
```bash
# Via Longhorn UI at https://longhorn.kng.house
# Navigate to Volume → home-assistant-home-assistant → Create Snapshot
```

2. **Restore from snapshot**:
```bash
# Scale down Home Assistant
kubectl scale deployment home-assistant -n home-assistant --replicas=0

# Restore volume via Longhorn UI
# Navigate to Volume → Create from Snapshot

# Update PVC to use restored volume
# Scale up Home Assistant
kubectl scale deployment home-assistant -n home-assistant --replicas=1
```

### External Backup (Recommended)

For off-cluster backups, copy from the backup PVC to external storage:

```bash
# Port-forward to access backups via HTTP
kubectl port-forward -n home-assistant svc/home-assistant 8123:8123

# Or mount the backup PVC and rsync
kubectl run -n home-assistant backup-sync --rm -it \
  --image=rclone/rclone:latest \
  --overrides='<see above for volume mount config>'

# Inside pod, sync to S3/NFS/etc
rclone sync /backups remote:homeassistant-backups
```

## Monitoring

### Metrics

Home Assistant exposes Prometheus metrics via ServiceMonitor:
- **Endpoint**: `http://home-assistant:8123/api/prometheus`
- **Interval**: 30s

View in Grafana:
```promql
homeassistant_sensor_state{entity="sensor.temperature"}
```

### Logs

View real-time logs:
```bash
kubectl logs -n home-assistant deployment/home-assistant -f
```

Check backup job logs:
```bash
kubectl logs -n home-assistant -l job-name=homeassistant-backup-<timestamp>
```

## Troubleshooting

### Database Connection Issues

Check database connectivity:
```bash
kubectl exec -n home-assistant deployment/home-assistant -- \
  nc -zv postgresql-primary.postgresql.svc.cluster.local 5432
```

Test database credentials:
```bash
kubectl exec -n postgresql postgresql-primary-0 -- \
  psql -U homeassistant -d homeassistant -c "SELECT version();"
```

### InfluxDB Connection Issues

Verify InfluxDB bucket:
```bash
kubectl exec -n influxdb influxdb-influxdb2-0 -- \
  influx bucket list --org influxdata
```

Test write access:
```bash
kubectl exec -n home-assistant deployment/home-assistant -- \
  curl -X POST "http://influxdb-influxdb2.influxdb.svc.cluster.local:8086/api/v2/write?org=influxdata&bucket=homeassistant" \
  -H "Authorization: Token <token>" \
  -d "test,host=homeassistant value=1"
```

### Storage Issues

Check PVC status:
```bash
kubectl get pvc -n home-assistant
```

Check Longhorn volume health:
```bash
kubectl get volumes.longhorn.io -n longhorn-system
```

View backup disk usage:
```bash
kubectl exec -n home-assistant deployment/home-assistant -- \
  df -h /config/backups
```

## Upgrade Procedure

1. **Backup current state**:
```bash
kubectl exec -n home-assistant deployment/home-assistant -- \
  ha backups new --name pre-upgrade-$(date +%Y%m%d)
```

2. **Update image tag in `values.yaml`**:
```yaml
image:
  tag: "2024.12.2"  # New version
```

3. **Commit and let ArgoCD sync**:
```bash
git add cluster/home/home-assistant/values.yaml
git commit -m "Upgrade Home Assistant to 2024.12.2"
git push
```

4. **Monitor upgrade**:
```bash
kubectl rollout status deployment/home-assistant -n home-assistant
kubectl logs -n home-assistant deployment/home-assistant -f
```

5. **Verify functionality** and rollback if needed:
```bash
# Rollback
kubectl rollout undo deployment/home-assistant -n home-assistant

# Restore from backup if needed
kubectl exec -n home-assistant deployment/home-assistant -- \
  ha backups restore <pre-upgrade-backup>
```

## Security Notes

1. **Database Credentials**: Stored in sealed-secret, never committed in plain text
2. **InfluxDB Token**: Generated during initialization, stored in sealed-secret
3. **Ingress**: TLS-enabled with Let's Encrypt certificates
4. **Network Policies**: Consider adding NetworkPolicy to restrict traffic
5. **Privileged Mode**: Required for device access (USB dongles, etc.)

## Resources

- [Home Assistant Documentation](https://www.home-assistant.io/docs/)
- [PostgreSQL Recorder Integration](https://www.home-assistant.io/integrations/recorder/)
- [InfluxDB Integration](https://www.home-assistant.io/integrations/influxdb/)
- [Backup & Restore](https://www.home-assistant.io/common-tasks/os/#backups)
