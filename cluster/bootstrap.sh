#!/bin/bash

total_steps=7
current_step=1

create_secrets() {
  kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/cert-manager.yaml > apps/networking/cert-manager/secret.yaml
  kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/external-dns.yaml > apps/networking/external-dns/secret.yaml
  kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/grafana-secret.yaml > apps/monitoring/kube-prometheus/grafana-secret.yaml
  kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/authentik-secret.yaml > apps/security/authentik/secret.yaml
  kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/db-authentik-credentials.yaml > apps/databases/pg-clusters/authentik/secret.yaml
  kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/db-homeassistant-credentials.yaml > apps/databases/pg-clusters/home-assistant/secret.yaml
  kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/influxdb-credentials.yaml > apps/databases/influxdb/secret.yaml
  kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/pgadmin-envs-secret.yaml > apps/databases/pgadmin/pgadmin-envs-secret.yaml
  kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/pgadmin-secret.yaml > apps/databases/pgadmin/pgadmin-secret.yaml
  kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/argocd-sso-secret.yaml > apps/core/argocd/argocd-sso-secret.yaml
}

show_progress() {
  if [[ $1 == sleep* ]]; then
    duration=${1##sleep }
    for ((remaining_time=duration; remaining_time>0; remaining_time--)); do
      printf "\r[$current_step/$total_steps] Sleeping... %d seconds remaining   " $remaining_time
      sleep 1
    done
    echo ""
  else
    echo -ne "\r[$current_step/$total_steps] $1"
    eval $1
    echo ""
  fi
  ((current_step++))
}

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [--secrets-only]"
  exit 1
fi

if [[ $1 == "--secrets-only" ]]; then
  show_progress "kustomize build --enable-alpha-plugins --enable-helm apps/core/sealed-secrets/ | kubectl apply -f -"
  show_progress "sleep 120"
  show_progress "kustomize build --enable-alpha-plugins --enable-helm apps/networking/kube-vip/ | kubectl apply -f -"
  show_progress "rm -rf apps/core/sealed-secrets/charts"
  show_progress "rm -rf apps/networking/kube-vip/charts"
  create_secrets
elif [[ $1 == "--no-secrets" ]]; then
  show_progress "kustomize build --enable-alpha-plugins --enable-helm apps/networking/ingress-nginx/ | kubectl apply -f -"
  show_progress "kustomize build --enable-alpha-plugins --enable-helm apps/networking/cert-manager/ | kubectl apply -f -"
  show_progress "kustomize build --enable-alpha-plugins --enable-helm apps/networking/external-dns/ | kubectl apply -f -"
  show_progress "sleep 240"
  show_progress "kustomize build --enable-alpha-plugins --enable-helm apps/core/argocd/ | kubectl apply -f -"
  show_progress "sleep 240"
  show_progress "kustomize build --enable-alpha-plugins --enable-helm argo-apps/ | kubectl apply -f -"
  show_progress "kubectl apply -f argo-apps/argo-projects.yaml"
  show_progress "kubectl apply -f argo-apps/root-app.yaml"
  show_progress "rm -rf apps/networking/ingress-nginx/charts"
  show_progress "rm -rf apps/networking/cert-manager/charts"
  show_progress "rm -rf apps/networking/external-dns/charts"
  show_progress "rm -rf apps/core/argocd/charts"
fi