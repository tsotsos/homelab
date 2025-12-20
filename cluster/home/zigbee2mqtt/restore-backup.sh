#!/bin/bash
# Zigbee2MQTT Disaster Recovery Script
# 
# Usage:
#   ./restore-backup.sh <backup-file>
#   
# Example:
#   ./restore-backup.sh zigbee2mqtt-backup-20251220-030000.tar.gz

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <backup-file>"
    echo ""
    echo "Available backups:"
    kubectl exec -n zigbee2mqtt statefulset/zigbee2mqtt -- ls -lh /backups/*.tar.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_FILE="$1"

echo "=== Zigbee2MQTT Disaster Recovery ==="
echo "Backup file: $BACKUP_FILE"
echo ""

# Confirm restoration
read -p "This will overwrite current Zigbee2MQTT configuration. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Restore cancelled"
    exit 0
fi

echo "Scaling down Zigbee2MQTT..."
kubectl scale statefulset -n zigbee2mqtt zigbee2mqtt --replicas=0

echo "Waiting for pod to terminate..."
kubectl wait --for=delete pod -l app.kubernetes.io/name=zigbee2mqtt -n zigbee2mqtt --timeout=60s || true

echo "Restoring backup..."
kubectl run -n zigbee2mqtt restore-pod --rm -i --image=alpine --overrides='
{
  "spec": {
    "securityContext": {
      "runAsNonRoot": true,
      "runAsUser": 1000,
      "seccompProfile": {
        "type": "RuntimeDefault"
      }
    },
    "containers": [{
      "name": "restore",
      "image": "alpine",
      "command": ["sh", "-c"],
      "args": ["
        set -e
        apk add --no-cache tar gzip
        echo \"Extracting backup...\"
        cd /data
        tar -xzf /backups/'"$BACKUP_FILE"'
        BACKUP_DIR=\$(tar -tzf /backups/'"$BACKUP_FILE"' | head -1 | cut -f1 -d\"/\")
        echo \"Restoring files from \$BACKUP_DIR...\"
        cp -vf \$BACKUP_DIR/* /data/
        rm -rf \$BACKUP_DIR
        echo \"✓ Restore completed\"
        ls -lh /data/
      "],
      "securityContext": {
        "allowPrivilegeEscalation": false,
        "capabilities": {
          "drop": ["ALL"]
        }
      },
      "volumeMounts": [
        {
          "name": "data",
          "mountPath": "/data"
        },
        {
          "name": "backups",
          "mountPath": "/backups",
          "readOnly": true
        }
      ]
    }],
    "volumes": [
      {
        "name": "data",
        "persistentVolumeClaim": {
          "claimName": "data-volume-zigbee2mqtt-0"
        }
      },
      {
        "name": "backups",
        "persistentVolumeClaim": {
          "claimName": "zigbee2mqtt-backups"
        }
      }
    ],
    "restartPolicy": "Never"
  }
}'

echo ""
echo "Scaling up Zigbee2MQTT..."
kubectl scale statefulset -n zigbee2mqtt zigbee2mqtt --replicas=1

echo ""
echo "✓ Disaster recovery completed successfully"
echo "Monitor startup: kubectl logs -n zigbee2mqtt -f statefulset/zigbee2mqtt"
