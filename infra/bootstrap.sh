#!/bin/bash

# --- Configuration ---
USER="root"
TLS_SAN="10.0.2.40"
HOMELAB="$HOME/Projects/homelab"
KUBECONFIG_PATH="$HOMELAB/k3s.yaml"
SECRETS="$HOMELAB/secrets.env"
K3S_CHANNEL="stable"
K3S_EXTRA_ARGS="--disable traefik --disable servicelb"
source $SECRETS

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Functions ---
install_server() {
  local ip="$1"
  echo -e "${BLUE}Installing server: $ip${NC}"
  k3sup install \
    --ip "$ip" \
    --user "$USER" \
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
  # Wait for server to come back online (adjust as needed)
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
  # Install first server
  install_server "${SERVERS[0]}"
  kustomize build --enable-alpha-plugins --enable-helm $HOMELAB/cluster/apps/networking/kube-vip/ | kubectl apply -f -
  rm -rf $HOMELAB/cluster/apps/networking/kube-vip/charts
else
  echo -e "${YELLOW}Choose an option:${NC}"
  echo "  a) Join all remaining servers"
  echo "  b) Join all agents"
  echo "  c) Join all servers and agents"
  read -r -p "Enter your choice [a/b/c]: " choice

  case "$choice" in
    a)
      echo -e "${YELLOW}Joining remaining servers...${NC}"
      total_servers=$((${#SERVERS[@]} - 1))
      current_server=1
      for i in "${!SERVERS[@]}"; do
        if [[ $i -ne 0 ]]; then
          join_server "${SERVERS[$i]}"
          show_progress $current_server $total_servers
          current_server=$((current_server + 1))
        fi
      done
      printf "\n"
      ;;
    b)
      echo -e "${YELLOW}Joining agents...${NC}"
      total_agents=${#AGENTS[@]}
      current_agent=1
      for agent_ip in "${AGENTS[@]}"; do
        join_agent "$agent_ip"
        show_progress $current_agent $total_agents
        current_agent=$((current_agent + 1))
      done
      printf "\n"
      ;;
    c)
      echo -e "${YELLOW}Joining remaining servers...${NC}"
      total_servers=$((${#SERVERS[@]} - 1))
      current_server=1
      for i in "${!SERVERS[@]}"; do
        if [[ $i -ne 0 ]]; then
          join_server "${SERVERS[$i]}"
          show_progress $current_server $total_servers
          current_server=$((current_server + 1))
        fi
      done
      printf "\n"

      echo -e "${YELLOW}Joining agents...${NC}"
      total_agents=${#AGENTS[@]}
      current_agent=1
      for agent_ip in "${AGENTS[@]}"; do
        join_agent "$agent_ip"
        show_progress $current_agent $total_agents
        current_agent=$((current_agent + 1))
      done
      printf "\n"
      ;;
    *)
      echo -e "${RED}Invalid choice!${NC}"
      ;;
  esac
fi

echo -e "${GREEN}Done!${NC}"