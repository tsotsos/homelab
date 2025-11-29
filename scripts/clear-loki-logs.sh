#!/bin/bash
# Clear all Loki logs and data
# WARNING: This will delete ALL logs permanently!

set -e

echo "🗑️  Clearing Loki logs..."
echo ""
echo "⚠️  WARNING: This will delete ALL logs permanently!"
echo "Press Ctrl+C within 5 seconds to cancel..."
sleep 5

echo ""
echo "📦 Scaling down Loki..."
kubectl scale statefulset loki -n loki --replicas=0

echo "⏳ Waiting for Loki to shut down..."
kubectl wait --for=delete pod -l app.kubernetes.io/name=loki -n loki --timeout=60s 2>/dev/null || true
sleep 5

echo "🧹 Deleting PVC data (this will trigger PV deletion with Longhorn)..."
kubectl delete pvc -n loki storage-loki-0 --wait=false 2>/dev/null || echo "PVC already deleted or doesn't exist"

echo "⏳ Waiting for PVC to be deleted..."
sleep 10

echo "📦 Scaling Loki back up..."
kubectl scale statefulset loki -n loki --replicas=1

echo "⏳ Waiting for Loki to start..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=loki -n loki --timeout=120s

echo ""
echo "✅ Loki logs cleared! Fresh start with empty data."
echo "📊 Check status: kubectl get pods -n loki"
