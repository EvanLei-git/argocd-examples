# ArgoCD & NGINX Ingress Setup & Notes

## Setup Commands

Run these commands in order to completely install and configure ArgoCD and the necessary Ingress controllers:

```bash
# 1. Install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Before you run the Helm command though, know what tool you are using to run your local Kubernetes cluster (e.g., Docker Desktop, Minikube, Kind, k3d, or Rancher Desktop).
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace

# 2. Install/Upgrade Traefik (if using Traefik as an alternative Ingress)
helm upgrade traefik traefik/traefik --namespace traefik --create-namespace

# 3. Install/Upgrade ArgoCD
helm upgrade argocd argo/argo-cd -f argocd-values.yaml --namespace argocd --create-namespace
```

## Debugging Information & Notes

### Missing Ingress Controller ("Gotcha" in Kubernetes)

Ah! This explains everything, and it is one of the most common "gotchas" in Kubernetes.

If `kube-dns` is the only service you see in that list, it means you do not have an Nginx Ingress Controller installed in your cluster yet.

**Here is what is happening:**
In your `values.yaml` files, you set `ingressClassName: nginx`. In Kubernetes, this creates an Ingress Resource, which is essentially just a piece of paper that says, "Hey Nginx, please route `jenkins.localhost` to me."

However, Kubernetes does not come with Nginx pre-installed. You wrote the instruction manual, but you haven't actually hired the "receptionist" to read it yet! Because the Nginx controller doesn't exist, your cluster is completely ignoring those routing rules.

**To fix this**, we need to install the Nginx Ingress Controller (which is included in the Setup Commands above).

Once that finishes installing, if you go back to `k9s` and type `:svc all`, you will finally see the `ingress-nginx-controller` appear, and you can port-forward it exactly as discussed!
