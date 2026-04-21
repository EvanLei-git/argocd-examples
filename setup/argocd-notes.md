 helm upgrade my-argocd argo/argo-cd -f argocd-values.yaml --namespace argocd --create-namespace





 Ah! This explains everything, and it is one of the most common "gotchas" in Kubernetes.

If kube-dns is the only service you see in that list, it means you do not have an Nginx Ingress Controller installed in your cluster yet.

Here is what is happening:
In your values.yaml files, you set ingressClassName: nginx. In Kubernetes, this creates an Ingress Resource, which is essentially just a piece of paper that says, "Hey Nginx, please route jenkins.localhost to me."

However, Kubernetes does not come with Nginx pre-installed. You wrote the instruction manual, but you haven't actually hired the "receptionist" to read it yet! Because the Nginx controller doesn't exist, your cluster is completely ignoring those routing rules.

To fix this, we need to install the Nginx Ingress Controller.

If you have Helm installed on your machine, you can add the official Nginx repository and install the controller by running these two commands in your terminal:

Bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
Once that finishes installing, if you go back to k9s and type :svc all, you will finally see the ingress-nginx-controller appear, and you can port-forward it exactly as we discussed!

Before you run that Helm command though, what tool are you using to run your local Kubernetes cluster (e.g., Docker Desktop, Minikube, Kind, k3d, or Rancher Desktop)?

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace

  helm upgrade traefik traefik/traefik --namespace traefik --create-namespace
