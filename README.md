# ArgoCD Examples & Local Setup

This branch contains the setup, configuration, and debugging notes for establishing a local Kubernetes development environment. It focuses on deploying and managing key infrastructure components using Helm, including:
- **ArgoCD**: For continuous delivery and GitOps.
- **Jenkins**: For continuous integration pipelines.
- **Traefik & NGINX**: As Ingress controllers to manage local routing (e.g., `argocd.localhost`, `jenkins.localhost`).

## Initial Infrastructure Setup (Umbrella Chart)

The cluster's core infrastructure (ArgoCD, Jenkins, and Ingress) is managed by a single unified Helm Umbrella Chart located in `setup/umbrella-chart/setup`. The configuration defaults to omitting hostnames so it can be safely used locally or in the cloud (where an IP/hostname is added externally).

### 1. Update Chart Dependencies
First, ensure you have the required repositories and update the dependencies:
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add jenkins https://charts.jenkins.io
helm repo add traefik https://traefik.github.io/charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

cd setup/umbrella-chart/setup
helm dependency update
```

### 2. Deploy Infrastructure

**Option A: Deploy using Traefik**
```bash
helm upgrade --install setup-cluster . -f values-traefik.yaml
```

**Option B: Deploy using NGINX**
```bash
helm upgrade --install setup-cluster . -f values-nginx.yaml
```



# EXTRA-MIGHT-DELETE

## Application Deployment

To build and apply Kustomize configurations with Helm support locally:
```bash
kustomize build ./dev --enable-helm | kubectl apply -f -
```


## Useful Commands

- Search for Helm chart versions: `helm search repo bitnami/redis --versions`
- If `k9s` logs aren't showing up, describe the pod directly for debugging:
  ```bash
  kubectl describe pod -l app.kubernetes.io/name=postgresql -n dev-env
  ```