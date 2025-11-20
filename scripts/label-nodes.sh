#!/bin/bash
set -e

echo "🏷️  Applying node role labels..."

# Apply worker role to all worker nodes
# Note: node-role.kubernetes.io/* labels are protected and cannot be set via Talos machine config
# They must be applied manually after cluster bootstrap

echo "▶ Labeling worker nodes with node-role.kubernetes.io/worker..."

kubectl label nodes \
  kng-worker-1 \
  kng-worker-2 \
  kng-worker-3 \
  kng-worker-4 \
  kng-worker-5 \
  kng-worker-6 \
  node-role.kubernetes.io/worker=worker \
  --overwrite

echo ""
echo "✅ Worker role labels applied successfully!"
echo ""
echo "📊 Current node roles:"
kubectl get nodes

echo ""
echo "🏷️  All node labels:"
kubectl get nodes --show-labels | grep -E "NAME|kng-worker" | cut -d' ' -f1,6-
