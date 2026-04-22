# ArgoCD Examples & Local Setup

This branch contains the setup, configuration, and debugging notes for establishing a local Kubernetes development environment. It focuses on deploying and managing key infrastructure components using Helm, including:
- **ArgoCD**: For continuous delivery and GitOps.
- **Jenkins**: For continuous integration pipelines.
- **Traefik & NGINX**: As Ingress controllers to manage local routing (e.g., `argocd.localhost`, `jenkins.localhost`).

## Local Deployment

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