# Cilium TLS/HTTPS Fix

## Issue
Envoy in standalone DaemonSet mode needs:
1. Group 1337 membership to access xds.sock (permissions: root:1337)
2. Cilium agent needs RBAC to read secrets from cilium-secrets namespace for SDS

## Solution

### 1. RBAC for Cilium Agent (rbac.yaml)
Created Role and RoleBinding to allow Cilium agent to read secrets in cilium-secrets namespace.

### 2. Envoy supplementalGroups
The Cilium Helm chart doesn't expose a way to set pod-level securityContext for Envoy.
Manual patch required:

```bash
kubectl patch ds cilium-envoy -n kube-system --type=strategic -p '{"spec":{"template":{"spec":{"securityContext":{"supplementalGroups":[1337]}}}}}'
```

This patch adds group 1337 to Envoy pods so they can access the xds.sock Unix socket created by Cilium agent.

## Verification
```bash
# Check Envoy has correct groups
kubectl exec -n kube-system $(kubectl get pod -n kube-system -l app.kubernetes.io/name=cilium-envoy -o name | head -1) -- id
# Should show: groups=0(root),1337

# Test HTTPS
curl -I -k https://argocd.kng.house
# Should return 200 OK
```

## Note
The supplementalGroups patch will be lost if Cilium is upgraded/redeployed via Helm.
TODO: Find a way to persist this in Helm values or create a kustomize strategic merge patch.
