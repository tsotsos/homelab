# Home Assistant

**License:** GPL-3.0 - See [LICENSE](../../../LICENSE)

Home automation platform with PostgreSQL database and automated backups.

## Components

- Home Assistant Core: Latest stable
- PostgreSQL: Primary data storage
- Longhorn Storage: 20Gi config + 50Gi backups
- Automated Backups: Daily at 3 AM, 7 day retention

## Storage

- `/config` (20Gi): Configuration files
- `/config/backups` (50Gi): Automated backup archives

## Database

PostgreSQL recorder configured via environment variable:

```yaml
recorder:
  db_url: !env_var POSTGRES_URL
  purge_keep_days: 30
```

Database and user created by init job in `db-init.yaml`.

## Access

Ingress configured for TLS access. Initial setup requires onboarding wizard.

## Backups

Daily CronJob creates backups via:
```bash
ha core backup --name "backup-$(date +%Y%m%d-%H%M%S)"
```

Retention: 7 days (older backups auto-deleted)

## Restore

```bash
# List backups
kubectl exec -n home-assistant deployment/home-assistant -- ha backups list

# Restore specific backup
kubectl exec -n home-assistant deployment/home-assistant -- ha backups restore <slug>
```

## Monitoring

```bash
# View logs
kubectl logs -n home-assistant deployment/home-assistant -f

# Check status
kubectl get pods -n home-assistant
```
