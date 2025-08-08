#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTERS_ROOT="$SCRIPT_DIR/../clusters"
CLUSTER="$1"
CLUSTER_PATH="${CLUSTERS_ROOT}/${CLUSTER}"

echo "🚀 Installing Cert Manager"
kustomize build --enable-helm "$CLUSTER_PATH"/cert-manager | kubectl apply -f -
rm -rf "$CLUSTER_PATH"/cert-manager/charts

echo "🚀 Installing Ingress Nginx"
kustomize build --enable-helm "$CLUSTER_PATH"/ingress-nginx | kubectl apply -f -
rm -rf "$CLUSTER_PATH"/ingress-nginx/charts

echo "🚀 Installing ArgoCd"
kustomize build --enable-helm "$CLUSTER_PATH"/argocd | kubectl apply -f -
rm -rf "$CLUSTER_PATH"/argocd/charts

echo "⏳ Waiting for Argo CD server to be ready..."
kubectl rollout status deployment/argocd-server -n argocd

echo "🔑 Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

echo "✅ Argo CD is installed and ready."

kubectl apply -f "$CLUSTER_PATH"/management-cluster.yaml
