# KNG Cluster Complete Rebuild Plan

**Date:** 2025-12-31  
**Objective:** Clean rebuild of Talos Kubernetes cluster with proper configuration, fixing all issues

---

## Pre-Rebuild Checklist

### Current Working Configuration to Preserve
- ✅ Longhorn v1.7.2 LTS (works on kng-2)
- ✅ Talos patches (common.yaml, kng-1/2/3.yaml)
- ✅ Cilium values.yaml with ingress controller
- ✅ Certificate configs for Let's Encrypt
- ✅ All sealed-secrets unsealed sources in secrets-un/

### Issues to Fix
- ❌ Cilium TLS secret sync (needs manual copying or auto-sync)
- ❌ ArgoCD Application OutOfSync states
- ❌ Cluster debris from multiple reinstalls
- ❌ Missing ServerSideApply configuration

---

## Phase 1: Talos Complete Wipe & Reinstall

### 1.1 Preparation (Local Machine)
```bash
cd /Users/george/Projects/homelab/infra/talos

# Verify Talos image hash
TALOS_IMAGE="508e4d5386e2d006af59e38dbeac5c0c5f7d43c383cf6d7ed2833d256526be2a"

# Verify all patches exist
ls -la patches/common.yaml patches/kng-{1,2,3}.yaml

# Check secrets.yaml exists (for regeneration if needed)
ls -la secrets.yaml
```

### 1.2 Wipe All Nodes (One by One)
**For each node (kng-1, kng-2, kng-3):**

```bash
# Reset node to factory state
talosctl reset --nodes 10.0.1.21 --graceful=false --reboot

# Wait for node to become accessible via DHCP temporary IP
# Check your DHCP server or router to find the temp IP
```

### 1.3 Bootstrap kng-1 (First Control Plane)
```bash
# Generate fresh cluster config (or use existing if secrets.yaml exists)
# If regenerating:
talosctl gen config kng-cluster https://10.0.1.100:6443 \
  --config-patch @patches/common.yaml \
  --force

# Apply config to kng-1 with its specific patch
TEMP_IP_KNG1="<DHCP_IP>"  # Replace with actual DHCP IP
talosctl apply-config --insecure \
  --nodes $TEMP_IP_KNG1 \
  --file controlplane.yaml \
  --config-patch @patches/kng-1.yaml

# Wait for reboot and static IP to come online (~2-3 minutes)
# Verify: ping 10.0.1.21

# Update talosconfig to point to kng-1
talosctl config endpoint 10.0.1.21
talosctl config node 10.0.1.21

# Bootstrap etcd
talosctl bootstrap --nodes 10.0.1.21

# Wait for cluster to initialize (~30 seconds)
talosctl health --nodes 10.0.1.21

# Get kubeconfig
talosctl kubeconfig --nodes 10.0.1.21 --force
export KUBECONFIG="$PWD/kubeconfig"

# Verify single-node cluster
kubectl get nodes
# Expected: kng-1 should be Ready (may show NotReady initially, wait 30s)
```

### 1.4 Join kng-2
```bash
TEMP_IP_KNG2="<DHCP_IP>"
talosctl apply-config --insecure \
  --nodes $TEMP_IP_KNG2 \
  --file controlplane.yaml \
  --config-patch @patches/kng-2.yaml

# Wait for reboot and join (~2-3 minutes)
# Verify: ping 10.0.1.22

# Check cluster
kubectl get nodes
# Expected: Both kng-1 and kng-2 should be Ready
```

### 1.5 Join kng-3
```bash
TEMP_IP_KNG3="<DHCP_IP>"
talosctl apply-config --insecure \
  --nodes $TEMP_IP_KNG3 \
  --file controlplane.yaml \
  --config-patch @patches/kng-3.yaml

# Wait for reboot and join (~2-3 minutes)
# Verify: ping 10.0.1.23

# Final cluster check
kubectl get nodes -o wide
# Expected: All 3 nodes Ready

# Update talosconfig to use all endpoints
talosctl config endpoint 10.0.1.21 10.0.1.22 10.0.1.23
talosctl config node 10.0.1.21 10.0.1.22 10.0.1.23
```

### 1.6 Verification
```bash
# Check cluster health
kubectl get nodes -o wide
kubectl get pods -A
# Expected: Only etcd, api-server, controller-manager, scheduler running

# Verify Talos health
talosctl health --nodes 10.0.1.21,10.0.1.22,10.0.1.23

# Check no CNI yet (nodes will be NotReady - this is expected)
```

**Checkpoint:** Bare Talos cluster with 3 control planes, no CNI, no workloads

---

## Phase 2: Install Cilium CNI with TLS Fix

### 2.1 Review Cilium Configuration
```bash
cd /Users/george/Projects/homelab

# Check current values.yaml
cat cluster/network/cilium/values.yaml

# Current config has:
# - ingressController.secretsNamespace.sync: true
# But this doesn't work properly (requires Cilium operator RBAC)
```

### 2.2 Decision: Cilium TLS Secret Strategy

**Option A: Enable Cilium Secret Sync (Preferred)**
- Cilium reads secrets from each namespace automatically
- Requires: Cilium operator needs RBAC to read secrets from all namespaces
- Pro: Automatic, no manual copying
- Con: Requires cluster-wide RBAC permissions for Cilium operator

**Option B: Manual Secret Copy Automation**
- Create a controller/CronJob that copies TLS secrets to cilium-secrets namespace
- Watches for cert-manager Certificate resources
- Automatically copies with correct naming: `{namespace}-{secret-name}`
- Pro: Works with current setup
- Con: Additional component to maintain

**RECOMMENDATION: Option A with proper RBAC**

### 2.3 Install Cilium with Fixed Configuration
```bash
cd /Users/george/Projects/homelab/infra/talos

# Install Cilium
./install.sh --cilium

# Wait for nodes to become Ready
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Verify Cilium status
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl exec -n kube-system ds/cilium -- cilium status
```

### 2.4 Apply Envoy Patch for TLS
```bash
# Apply supplementalGroups patch for Envoy to access xds.sock
kubectl patch ds cilium-envoy -n kube-system --type=strategic \
  -p '{"spec":{"template":{"spec":{"securityContext":{"supplementalGroups":[1337]}}}}}'

# Wait for Envoy to restart
kubectl rollout status ds/cilium-envoy -n kube-system

# Verify Envoy has group 1337
kubectl exec -n kube-system $(kubectl get pod -n kube-system -l app.kubernetes.io/name=cilium-envoy -o name | head -1) -- id
# Should show: groups=0(root),1337
```

### 2.5 Create Cilium Operator RBAC for Secret Reading
**Create file: `cluster/network/cilium/secret-reader-rbac.yaml`**
```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cilium-operator-secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cilium-operator-secret-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cilium-operator-secret-reader
subjects:
- kind: ServiceAccount
  name: cilium-operator
  namespace: kube-system
```

Apply:
```bash
kubectl apply -f cluster/network/cilium/secret-reader-rbac.yaml
```

### 2.6 Update Cilium Values for Secret Sync
**Edit: `cluster/network/cilium/values.yaml`**
Ensure these settings are present:
```yaml
ingressController:
  enabled: true
  default: true
  loadbalancerMode: shared
  service:
    type: LoadBalancer
  secretsNamespace:
    create: true
    name: cilium-secrets
    sync: true
```

**Checkpoint:** Cilium installed, Envoy can handle TLS, RBAC configured for secret reading

---

## Phase 3: Install Core Infrastructure

### 3.1 Install kube-vip and kube-vip-cloud-provider
```bash
cd /Users/george/Projects/homelab/infra/talos
./install.sh --kube-vip

# Verify LoadBalancer service capability
kubectl get svc -n kube-system
```

### 3.2 Install Sealed Secrets Controller
```bash
./install.sh --sealed-secrets

# Wait for controller to be ready
kubectl wait --for=condition=Available deployment/sealed-secrets -n kube-system --timeout=120s
```

### 3.3 Seal All Secrets
```bash
# Ensure unsealed secrets exist
ls -la ../secrets-un/

# Seal all secrets
./install.sh --seal-secrets

# Verify sealed secrets created in cluster directories
find ../cluster -name "sealed-secret.yaml"
```

### 3.4 Install external-dns
```bash
./install.sh --external-dns

# Verify
kubectl get pods -n external-dns
```

### 3.5 Install cert-manager
```bash
./install.sh --cert-manager

# Verify CRDs
kubectl get crd | grep cert-manager

# Verify ClusterIssuer
kubectl get clusterissuer letsencrypt-dns
# Should show: Ready=True
```

**Checkpoint:** Core infrastructure ready, secrets sealed, DNS and cert-manager operational

---

## Phase 4: Install Storage (Longhorn v1.7.2 LTS)

### 4.1 Verify Longhorn Configuration
```bash
cat cluster/storage/longhorn/kustomization.yaml
# Ensure version: 1.7.2

cat cluster/storage/longhorn/values.yaml
# Check:
# - defaultReplicaCount: 2
# - Persistence settings appropriate
```

### 4.2 Configure Longhorn for Efficiency
**Edit: `cluster/storage/longhorn/values.yaml`**

Add/verify these settings to prevent bloat:
```yaml
defaultSettings:
  defaultReplicaCount: 2
  
  # Prevent snapshot accumulation
  snapshotDataIntegrity: "fast-check"
  snapshotMaxCount: 10
  
  # Efficient space usage
  storageMinimalAvailablePercentage: 10
  storageOverProvisioningPercentage: 100
  
  # Fast failover
  replicaSoftAntiAffinity: true
  replicaAutoBalance: "least-effort"
  
  # Backup settings (optional)
  # backupTarget: "nfs://nas.kng.house:/mnt/backups/longhorn"
  # backupTargetCredentialSecret: ""
  
  # Optimize for performance
  guaranteedInstanceManagerCPU: 12
  
# Prevent pre-upgrade checks (for GitOps)
preUpgradeChecker:
  jobEnabled: false
  upgradeVersionCheck: false

# Persistence
persistence:
  defaultClass: true
  defaultFsType: ext4
  defaultClassReplicaCount: 2
  defaultDataLocality: disabled  # Can change to "best-effort" for better performance
```

### 4.3 Install Longhorn
```bash
cd /Users/george/Projects/homelab/infra/talos
./install.sh --longhorn

# Wait for all components (this takes ~5 minutes)
kubectl wait --for=condition=Ready pods -l app=longhorn-manager -n longhorn-system --timeout=300s

# Verify CSI plugin on all nodes
kubectl get pods -n longhorn-system -l app=longhorn-csi-plugin -o wide
# All 3 should be Running (especially kng-2!)

# Verify CSI driver registration
kubectl get csinode
kubectl get csinode kng-2 -o yaml | grep longhorn
# Should show: driver.longhorn.io

# Verify Longhorn nodes
kubectl get nodes.longhorn.io -n longhorn-system
# All 3 should be Ready and Schedulable
```

### 4.4 Test Longhorn on kng-2 Specifically
```bash
# Create test PVC on kng-2
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-kng2
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-kng2
  namespace: default
spec:
  nodeSelector:
    kubernetes.io/hostname: kng-2
  containers:
  - name: test
    image: busybox
    command: ['sh', '-c', 'echo "SUCCESS on kng-2!" > /data/test && cat /data/test && sleep 3600']
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-kng2
EOF

# Wait and verify
sleep 15
kubectl get pod test-kng2 -o wide
kubectl logs test-kng2
# Should show: "SUCCESS on kng-2!"

# Cleanup
kubectl delete pod test-kng2
kubectl delete pvc test-kng2
```

**Checkpoint:** Longhorn v1.7.2 installed and working on all 3 nodes including kng-2

---

## Phase 5: Install ArgoCD and ApplicationSet

### 5.1 Install ArgoCD
```bash
cd /Users/george/Projects/homelab/infra/talos
./install.sh --argocd

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
# Save this password!
```

### 5.2 Fix ApplicationSet Configuration
**Edit: `cluster/main.yaml`**

Ensure ignoreDifferences includes CRDs:
```yaml
spec:
  template:
    spec:
      syncPolicy:
        automated:
          prune: false
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          # DO NOT use ServerSideApply here - it causes field manager conflicts
      ignoreDifferences:
        - group: apps
          kind: StatefulSet
          jqPathExpressions:
            - '.spec.volumeClaimTemplates[]?.status'
            - '.spec.volumeClaimTemplates[]?.apiVersion'
            - '.spec.volumeClaimTemplates[]?.kind'
        - group: apiextensions.k8s.io
          kind: CustomResourceDefinition
          jqPathExpressions:
            - '.status'
            - '.metadata.annotations."kubectl.kubernetes.io/last-applied-configuration"'
```

### 5.3 Apply ApplicationSet
```bash
cd /Users/george/Projects/homelab

# Review main.yaml
cat cluster/main.yaml

# Apply AppProject, ArgoCD app, and ApplicationSet
kubectl apply -f cluster/main.yaml

# Wait for ApplicationSet to generate applications
sleep 15

# Check generated applications
kubectl get applications -n argocd
```

### 5.4 Initial Sync
```bash
# All applications should auto-sync
# Monitor progress
watch kubectl get applications -n argocd

# If any are stuck OutOfSync, manually sync:
kubectl patch application <app-name> -n argocd --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

**Checkpoint:** ArgoCD managing all applications via ApplicationSet

---

## Phase 6: Deploy Applications

### 6.1 Verify Critical Apps First

**Check these in order:**
1. **Cilium** - Should already be healthy
2. **cert-manager** - Verify ClusterIssuer ready
3. **external-dns** - Check for DNS updates
4. **Longhorn** - All nodes ready
5. **kube-prometheus-stack** - Wait for CRDs to be established

```bash
# Monitor application sync status
kubectl get applications -n argocd -w
```

### 6.2 Fix Authentik (Requires PostgreSQL Init)
Authentik needs PostgreSQL database created first.

```bash
# Wait for PostgreSQL to be healthy
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=postgresql -n postgresql --timeout=300s

# Check if authentik database exists
kubectl exec -it postgresql-primary-0 -n postgresql -- psql -U postgres -c "\l"

# If authentik database doesn't exist, it should be created by PostgreSQL init scripts
# Check PostgreSQL sealed-secret has correct init scripts

# Sync Authentik after PostgreSQL is ready
kubectl get application authentik -n argocd
```

### 6.3 Configure Local Storage for Hot Data
For time-series databases (kube-prometheus, loki, influxdb):

**Edit each application's values to use local-path-nvme:**
- `cluster/observability/kube-prometheus-stack/values.yaml`
- `cluster/observability/loki/values.yaml`
- `cluster/observability/influxdb/values.yaml` (decision pending)

Example for Prometheus:
```yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path-nvme  # Fast NVMe
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi
```

### 6.4 Verify All Applications
```bash
# Check all application statuses
kubectl get applications -n argocd

# Check all pods across namespaces
kubectl get pods -A | grep -vE "Running|Completed"

# Check for any errors
kubectl get events -A --sort-by='.lastTimestamp' | grep -i error
```

**Checkpoint:** All applications deployed and healthy

---

## Phase 7: Verify TLS and Ingress

### 7.1 Check Certificate Issuance
```bash
# List all certificates
kubectl get certificate -A

# Check a specific certificate
kubectl describe certificate argocd-server-tls -n argocd

# Verify secret created
kubectl get secret argocd-server-tls -n argocd
```

### 7.2 Verify Cilium Secret Sync
```bash
# Check if secrets are in cilium-secrets namespace
kubectl get secrets -n cilium-secrets

# If empty and Cilium secret sync isn't working, check:
kubectl logs -n kube-system deployment/cilium-operator | grep -i secret

# Verify RBAC
kubectl auth can-i get secrets --as=system:serviceaccount:kube-system:cilium-operator --all-namespaces
# Should return: yes
```

### 7.3 Test HTTPS Ingress
```bash
# Test ArgoCD
curl -I https://argocd.kng.house
# Should return: 200 OK

# Test InfluxDB
curl -I https://influxdb.kng.house

# Test other ingresses
kubectl get ingress -A
```

### 7.4 Manual Secret Copy (If Auto-Sync Fails)
If Cilium secret sync still doesn't work:
```bash
# Copy each TLS secret with correct naming
for namespace in argocd influxdb longhorn; do
  SECRET_NAME="${namespace}-tls"
  if kubectl get secret $SECRET_NAME -n $namespace &>/dev/null; then
    kubectl get secret $SECRET_NAME -n $namespace -o yaml | \
      sed "s/name: ${SECRET_NAME}/name: ${namespace}-${SECRET_NAME}/" | \
      sed "s/namespace: ${namespace}/namespace: cilium-secrets/" | \
      kubectl apply -f -
    echo "Copied: $namespace/$SECRET_NAME -> cilium-secrets/${namespace}-${SECRET_NAME}"
  fi
done
```

**Checkpoint:** All ingresses accessible via HTTPS

---

## Phase 8: Final Verification and Cleanup

### 8.1 Check All Deployments
```bash
# Get overview of all applications
kubectl get applications -n argocd

# Check all namespaces
kubectl get pods -A -o wide

# Check for any OutOfSync applications
kubectl get applications -n argocd | grep OutOfSync
```

### 8.2 Clean Up Debris
```bash
# Remove any stuck namespaces
kubectl get namespaces | grep Terminating

# If any stuck namespaces, force delete:
for ns in $(kubectl get namespaces | grep Terminating | awk '{print $1}'); do
  kubectl get namespace $ns -o json | \
    jq '.spec.finalizers = []' | \
    kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f -
done

# Remove any orphaned PVCs
kubectl get pvc -A | grep -i lost

# Remove test resources
kubectl delete pod,pvc -l app=test --all-namespaces

# Clean up failed pods
kubectl delete pods --field-selector status.phase=Failed -A
```

### 8.3 Verify Resource Usage
```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -A --sort-by=memory | head -20

# Check Longhorn disk usage
kubectl get nodes.longhorn.io -n longhorn-system -o wide

# Check PVC usage
kubectl get pvc -A
```

### 8.4 Document Cluster State
```bash
# Save cluster info
kubectl cluster-info > cluster-info.txt

# Save all application states
kubectl get applications -n argocd -o yaml > argocd-applications.yaml

# Save node labels
kubectl get nodes --show-labels > node-labels.txt

# Save storage classes
kubectl get storageclass -o wide > storageclasses.txt
```

**Checkpoint:** Clean cluster with no debris, all applications healthy

---

## Phase 9: Restore zigbee2mqtt from Backup
(Final step - will be done separately)

```bash
# Run restore script
cd /Users/george/Projects/homelab/cluster/home/zigbee2mqtt
./restore-backup.sh

# Verify
kubectl get pods -n zigbee2mqtt
```

---

## Phase 10: Post-Deployment Validation

### 10.1 Critical Service Checks
- [ ] All nodes Ready
- [ ] Cilium healthy (no CrashLoops)
- [ ] All CSI drivers registered (especially kng-2)
- [ ] Longhorn nodes all Ready
- [ ] ArgoCD accessible
- [ ] All applications Synced and Healthy
- [ ] HTTPS working on all ingresses
- [ ] Certificates valid
- [ ] External DNS creating records

### 10.2 Performance Checks
- [ ] API server responsive
- [ ] Pod creation fast (<30s)
- [ ] PVC binding fast (<1min)
- [ ] No excessive resource usage

### 10.3 HA Checks
- [ ] Reboot one node, services stay up
- [ ] API server accessible via VIP
- [ ] Workloads distributed across nodes

---

## Known Issues and Solutions

### Issue: Cilium TLS Secret Sync Not Working
**Solution:** Apply RBAC ClusterRole for cilium-operator to read secrets cluster-wide

### Issue: Longhorn CSI "exec format error" on kng-2
**Solution:** Stay on Longhorn v1.7.2 LTS (works with CSI v2.12.0)

### Issue: ArgoCD Applications OutOfSync for CRDs
**Solution:** Add ignoreDifferences for CRD status and metadata in ApplicationSet

### Issue: Envoy cannot access xds.sock
**Solution:** Apply supplementalGroups patch to add group 1337

### Issue: Namespace stuck in Terminating
**Solution:** Remove finalizers and webhooks blocking deletion

---

## Emergency Rollback Plan

If rebuild fails and needs to revert:

1. **Backup current state before starting:**
   ```bash
   talosctl kubeconfig --force > kubeconfig.backup
   kubectl get all -A -o yaml > cluster-state.yaml
   ```

2. **If Talos wipe fails mid-way:**
   - Can re-bootstrap any node individually
   - Other nodes will rejoin automatically

3. **If application deployment fails:**
   - Delete ApplicationSet: `kubectl delete applicationset kng-cluster -n argocd`
   - Fix configuration in git
   - Re-apply: `kubectl apply -f cluster/main.yaml`

---

## Execution Estimate

- **Phase 1 (Talos):** 30-45 minutes
- **Phase 2 (Cilium):** 15-20 minutes
- **Phase 3 (Core):** 20-30 minutes
- **Phase 4 (Longhorn):** 15-20 minutes
- **Phase 5 (ArgoCD):** 10-15 minutes
- **Phase 6 (Apps):** 30-45 minutes
- **Phase 7-9 (Verify/Clean):** 15-20 minutes

**Total: ~2-3 hours** (with time for verification at each phase)

---

## Ready to Execute?

Review this plan and confirm:
1. ✅ Talos image hash correct: `508e4d5386e2d006af59e38dbeac5c0c5f7d43c383cf6d7ed2833d256526be2a`
2. ✅ Longhorn version locked to v1.7.2
3. ✅ Cilium TLS strategy decided (RBAC for secret sync)
4. ✅ All unsealed secrets in `secrets-un/`
5. ✅ Ready to wipe cluster completely

**When ready, we'll execute phase by phase with verification at each step.**
