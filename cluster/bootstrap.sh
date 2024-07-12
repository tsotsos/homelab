#!/bin/zsh

total_steps=7
current_step=1

for command in \
  "kustomize build --enable-alpha-plugins --enable-helm apps/core/sealed-secrets/ | kubectl apply -f -" \
  "echo 'create secrets\n'"\
  "kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/cert-manager.yaml > apps/networking/cert-manager.yaml" \
  "kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/external-dns.yaml > apps/networking/extrenal-dns.yaml" \
  "kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/grafana-secret.yaml > apps/monitoring/kube-prometheus/grafana-secret.yaml" \
  "kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/authentik-secret.yaml > apps/security/authentik/secret.yaml" \
  "kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/db-authentik-credentials.yaml > apps/databases/pg-clusters/authentik/secret.yaml" \
  "kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/influxdb-credentials.yaml > apps/databases/influxdb/secret.yaml" \
  "kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/pgadmin-envs-secret.yaml > apps/databases/pgadmin/pgadmin-envs-secret.yaml" \
  "kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/pgadmin-secret.yaml > apps/databases/pgadmin/pgadmin-secret.yaml" \
  "kubeseal --scope cluster-wide --controller-name sealed-secrets --controller-namespace kube-system --format yaml --secret-file ../secrets-un/argocd-sso-secret.yaml > apps/core/argocd/argocd-sso-secret.yaml" \
  "echo '-----\n'"\
  "kustomize build --enable-alpha-plugins --enable-helm apps/networking/ingress-nginx/ | kubectl apply -f -" \
  "kustomize build --enable-alpha-plugins --enable-helm apps/networking/cert-manager/ | kubectl apply -f -" \
  "kustomize build --enable-alpha-plugins --enable-helm apps/networking/extrenal-dns/ | kubectl apply -f -" \
  "sleep 60" \
  "kustomize build --enable-alpha-plugins --enable-helm apps/core/argocd/ | kubectl apply -f -" \
  "sleep 60" \
  "kustomize build --enable-alpha-plugins --enable-helm argo-apps/ | kubectl apply -f -"; do
  if [[ $command == sleep* ]]; then
    duration=${command##sleep }
    end_time=$((SECONDS + duration)) 
    while ((SECONDS < end_time)); do
      remaining_time=$((end_time - SECONDS))
      print -n "\r[$(($current_step * 100 / $total_steps))%] Sleeping... $remaining_time seconds remaining   "
      sleep 1
    done
  else
    # normal progress bar
    ((current_step++)) && print -n "\r[$(($current_step * 100 / $total_steps))%] "
    eval $command
  fi
done
print ""