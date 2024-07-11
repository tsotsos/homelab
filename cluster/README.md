# Bootstrapping cluster

Assuming that KubeVip already installed via ansible role and cluster initialization.
To bootstrap cluster and initialize argocd we need:
* Sealed Secrets
* Ingress Nginx
* Cert Manager
* ArgoCD

To do that use kustomize with helm or `bootstrap.sh`

```bash
kustomize build --enable-alpha-plugins --enable-helm | kubectl apply -f -
```