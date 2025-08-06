#!/bin/bash

# --- Usage Example ---
# ./setup-k3s.sh myenv.env      # uses a custom env file

# --- Load environment variables ---
ENV_FILE="${1:-$HOME/Projects/homelab/secrets.env}"
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Env file not found: $ENV_FILE"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

# --- Required variables check ---
: "${USER:?Missing USER}"
: "${TLS_SAN:?Missing TLS_SAN}"
: "${K3S_EXTRA_ARGS:?Missing K3S_EXTRA_ARGS}"
: "${SERVERS:?Missing SERVERS array}"
: "${AGENTS:?Missing AGENTS array}"
: "${INSTALL_KUBE_VIP:=false}"  # default to false
: "${HOMELAB:=~/Projects/homelab}"
: "${KUBECONFIG_PATH:=$HOMELAB/k3s.yaml}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Functions ---
install_server() {
  local ip="$1"
  echo -e "${BLUE}Installing server: $ip${NC}"
  k3sup install \
    --ip "$ip" \
    --user "$USER" \
    --k3s-channel "$K3S_CHANNEL" \
    --tls-san "$TLS_SAN" \
    --cluster \
    --local-path "$KUBECONFIG_PATH" \
    --k3s-extra-args "$K3S_EXTRA_ARGS --node-ip=$ip"
  reboot_server "$ip"
}

join_server() {
  local ip="$1"
  echo -e "${BLUE}Joining server: $ip${NC}"
  k3sup join \
    --ip "$ip" \
    --user "$USER" \
    --k3s-channel "$K3S_CHANNEL" \
    --server \
    --server-ip "$TLS_SAN" \
    --server-user "$USER" \
    --sudo \
    --k3s-extra-args "$K3S_EXTRA_ARGS --node-ip=$ip"
  reboot_server "$ip"
}

join_agent() {
  local ip="$1"
  echo -e "${BLUE}Joining agent: $ip${NC}"
  k3sup join \
    --user "$USER" \
    --server-ip "$TLS_SAN" \
    --ip "$ip" \
    --k3s-channel "$K3S_CHANNEL" \
    --print-command
  reboot_server "$ip"
}

reboot_server() {
  local ip="$1"
  echo -e "${YELLOW}Rebooting server $ip...${NC}"
  ssh -o "StrictHostKeyChecking=no" "$USER@$ip" reboot
  sleep 60
}

show_progress() {
  local current="$1"
  local total="$2"
  local bar_length=50
  local filled_length=$((($bar_length * $current) / $total))
  local bar=$(printf "%${filled_length}s" '' | tr ' ' '#')
  printf "\r${GREEN}Progress: [%-${bar_length}s] %d/%d${NC}" "$bar" "$current" "$total"
}

# --- Wizard ---
echo -e "${YELLOW}K3s Cluster Setup Wizard${NC}"
read -r -p "Is this the first server? [y/N] " response
if [[ "$response" =~ ^[yY]$ ]]; then
  install_server "${SERVERS[0]}"

  if [[ "$INSTALL_KUBE_VIP" == "true" ]]; then
    echo -e "${YELLOW}Installing kube-vip...${NC}"
    kustomize build --enable-alpha-plugins --enable-helm "$HOMELAB/cluster/apps/networking/kube-vip/" | kubectl apply -f -
    rm -rf "$HOMELAB/cluster/apps/networking/kube-vip/charts"
  fi
else
  echo -e "${YELLOW}Choose an option:${NC}"
  echo "  a) Join all remaining servers"
  echo "  b) Join all agents"
  echo "  c) Join all servers and agents"
  read -r -p "Enter your choice [a/b/c]: " choice

  case "$choice" in
    a)
      total_servers=$((${#SERVERS[@]} - 1))
      current=1
      for i in "${!SERVERS[@]}"; do
        [[ $i -eq 0 ]] && continue
        join_server "${SERVERS[$i]}"
        show_progress $current $total_servers
        current=$((current + 1))
      done
      ;;
    b)
      total_agents=${#AGENTS[@]}
      current=1
      for agent_ip in "${AGENTS[@]}"; do
        join_agent "$agent_ip"
        show_progress $current $total_agents
        current=$((current + 1))
      done
      ;;
    c)
      total_servers=$((${#SERVERS[@]} - 1))
      current=1
      for i in "${!SERVERS[@]}"; do
        [[ $i -eq 0 ]] && continue
        join_server "${SERVERS[$i]}"
        show_progress $current $total_servers
        current=$((current + 1))
      done
      printf "\n"

      total_agents=${#AGENTS[@]}
      current=1
      for agent_ip in "${AGENTS[@]}"; do
        join_agent "$agent_ip"
        show_progress $current $total_agents
        current=$((current + 1))
      done
      ;;
    *)
      echo -e "${RED}Invalid choice!${NC}"
      ;;
  esac
fi

echo -e "${GREEN}Done!${NC}"
