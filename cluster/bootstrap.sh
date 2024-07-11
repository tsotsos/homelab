kustomize build --enable-alpha-plugins --enable-helm apps/networking/ingress-nginx/ | kubectl apply -f -
kustomize build --enable-alpha-plugins --enable-helm apps/networking/cert-manager/ | kubectl apply -f -
kustomize build --enable-alpha-plugins --enable-helm apps/core/sealed-secrets/ | kubectl apply -f -
sleep 60
kustomize build --enable-alpha-plugins --enable-helm apps/core/argocd/ | kubectl apply -f -