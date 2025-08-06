#!/bin/bash
set -euo pipefail

# === Config ===
ARGO_NS="argocd"
ARGO_HELM_VERSION="8.2.3"
VALUES_FILE="$(dirname "$0")/argocd-values.yaml"

echo "🚀 Adding Argo CD Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "📦 Creating namespace: $ARGO_NS"
kubectl create namespace "$ARGO_NS" --dry-run=client -o yaml | kubectl apply -f -

echo "📥 Installing Argo CD..."
helm upgrade --install argo-cd argo/argo-cd \
--namespace "$ARGO_NS" \
--version "$ARGO_HELM_VERSION"

echo "⏳ Waiting for Argo CD server to be ready..."
kubectl rollout status deployment/argo-cd-argocd-server -n "$ARGO_NS"

echo "🔑 Initial admin password:"
kubectl -n "$ARGO_NS" get secret argo-cd-argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

echo "✅ Argo CD is installed and ready."
