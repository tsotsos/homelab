#!/bin/bash
# Clear all Loki logs and data
# WARNING: This will delete ALL logs permanently!

set -e

NAMESPACE="logging"

echo "🗑️  Clearing Loki logs..."
echo ""
echo "⚠️  WARNING: This will delete ALL logs permanently!"
echo "Press Ctrl+C within 5 seconds to cancel..."
sleep 5

echo ""
echo "🔍 Checking if Loki is deployed..."
if ! kubectl get namespace $NAMESPACE &>/dev/null; then
  echo "❌ Namespace '$NAMESPACE' doesn't exist. Deploy Loki first."
  exit 1
fi

if ! kubectl get statefulset loki -n $NAMESPACE &>/dev/null; then
  echo "❌ Loki StatefulSet doesn't exist in namespace '$NAMESPACE'. Deploy Loki first."
  exit 1
fi

echo "📦 Scaling down Loki StatefulSet..."
kubectl scale statefulset loki -n $NAMESPACE --replicas=0

echo "⏳ Waiting for Loki to shut down..."
kubectl wait --for=delete pod -l app.kubernetes.io/name=loki -n $NAMESPACE --timeout=60s 2>/dev/null || true
sleep 5

echo "🧹 Deleting PVC data (this will trigger PV deletion with Longhorn)..."
PVCS=$(kubectl get pvc -n $NAMESPACE -o name 2>/dev/null | grep storage-loki || true)
if [ -n "$PVCS" ]; then
  echo "$PVCS" | xargs kubectl delete -n $NAMESPACE --wait=false 2>/dev/null || true
  echo "⏳ Waiting for PVCs to be deleted..."
  sleep 10
else
  echo "ℹ️  No Loki PVCs found to delete"
fi

echo "📦 Scaling Loki back up..."
kubectl scale statefulset loki -n $NAMESPACE --replicas=1

echo "⏳ Waiting for Loki to start..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=loki -n $NAMESPACE --timeout=120s

echo ""
echo "✅ Loki logs cleared! Fresh start with empty data."
echo "📊 Check status: kubectl get pods -n $NAMESPACE"
