#!/bin/bash
# This script injects secrets into zigbee2mqtt configuration.yaml
# It runs as an init container to merge secret values before zigbee2mqtt starts

set -e

CONFIG_FILE="/data/configuration.yaml"
TEMP_CONFIG="/tmp/configuration.yaml"

# Read secrets from environment variables
NETWORK_KEY="$Z2M_NETWORK_KEY"
EXT_PAN_ID="$Z2M_EXT_PAN_ID"
PAN_ID="$Z2M_PAN_ID"

echo "Injecting secrets into configuration..."

# Use yq or sed to inject values into configuration.yaml
# This assumes the configuration.yaml is already created by the helm chart
if [ -f "$CONFIG_FILE" ]; then
  cp "$CONFIG_FILE" "$TEMP_CONFIG"
  
  # Inject network_key, ext_pan_id, and pan_id into the advanced section
  # Using yq (if available) or python
  if command -v yq &> /dev/null; then
    yq eval ".advanced.network_key = $NETWORK_KEY" -i "$TEMP_CONFIG"
    yq eval ".advanced.ext_pan_id = $EXT_PAN_ID" -i "$TEMP_CONFIG"
    yq eval ".advanced.pan_id = $PAN_ID" -i "$TEMP_CONFIG"
  else
    # Fallback to Python
    python3 <<EOF
import yaml
import os

with open('$TEMP_CONFIG', 'r') as f:
    config = yaml.safe_load(f)

if 'advanced' not in config:
    config['advanced'] = {}

config['advanced']['network_key'] = eval(os.environ['Z2M_NETWORK_KEY'])
config['advanced']['ext_pan_id'] = eval(os.environ['Z2M_EXT_PAN_ID'])
config['advanced']['pan_id'] = os.environ['Z2M_PAN_ID']

with open('$TEMP_CONFIG', 'w') as f:
    yaml.dump(config, f)
EOF
  fi
  
  mv "$TEMP_CONFIG" "$CONFIG_FILE"
  echo "Configuration updated successfully"
else
  echo "Warning: Configuration file not found at $CONFIG_FILE"
  exit 1
fi
