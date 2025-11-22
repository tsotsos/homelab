#!/bin/bash
# =============================================================================
# NODE LABEL MANAGEMENT
# =============================================================================
# Applies node labels based on cluster-config.yaml configuration
# Labels include: node roles, workload types, and topology zones
#
# Usage: ./label-nodes.sh
#
# This script should be run after successful cluster bootstrap

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/infra/cluster-config.yaml"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}▶${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

# =============================================================================
# CHECK PREREQUISITES
# =============================================================================
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: cluster-config.yaml not found at $CONFIG_FILE"
    exit 1
fi

if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is required but not installed"
    exit 1
fi

# =============================================================================
# APPLY NODE LABELS
# =============================================================================
log "Applying node labels from cluster-config.yaml..."
echo ""

# Parse cluster-config.yaml and apply labels to each node
for node in $(yq eval '.nodes | keys | .[]' "$CONFIG_FILE"); do
    # Get node role
    role=$(yq eval ".nodes.\"$node\".role" "$CONFIG_FILE")
    
    # Skip if not a worker node (only workers get custom labels)
    if [ "$role" != "worker" ]; then
        continue
    fi
    
    info "Labeling node: $node"
    
    # Get all labels for this node
    labels=$(yq eval ".nodes.\"$node\".labels // {}" "$CONFIG_FILE" -o=json)
    
    # Apply each label
    echo "$labels" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' | while read -r label; do
        kubectl label node "$node" "$label" --overwrite 2>/dev/null || true
    done
done

echo ""
log "✅ Node labels applied successfully!"
echo ""

# =============================================================================
# DISPLAY RESULTS
# =============================================================================
log "Current node configuration:"
echo ""
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
ROLE:.metadata.labels.node-role\\.kubernetes\\.io/worker,\
ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone,\
APPS:.metadata.labels.node\\.kng/workload-apps,\
INFRA:.metadata.labels.node\\.kng/workload-infra,\
STORAGE:.metadata.labels.node\\.kng/workload-storage

echo ""
info "Legend:"
echo "  - APPS: General application workloads"
echo "  - INFRA: Infrastructure services (ArgoCD, Ingress, Cert-Manager, etc.)"
echo "  - STORAGE: Storage services (Longhorn)"
echo ""
