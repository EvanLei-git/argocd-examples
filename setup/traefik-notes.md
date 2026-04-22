# Traefik Setup & Notes

## Setup Commands

Run these commands in order to completely install and configure Traefik:

```bash
# 1. Add and update the Traefik Helm repository
helm repo add traefik https://helm.traefik.io/traefik
helm repo update

# 2. Install Traefik using the values file
helm install traefik traefik/traefik --namespace traefik --create-namespace --values values.yaml

# 3. Upgrade Traefik (when modifying values)
helm upgrade traefik traefik/traefik -n traefik -f traefik-values.yaml

# 4. Example Upgrade: Redirecting HTTP to HTTPS
helm upgrade traefik traefik/traefik \
  --namespace traefik \
  --reuse-values \
  --set ports.web.redirectTo.port=websecure
```

## Debugging Information & Notes

### 1. The Helm Upgrade Error
- **The Error:** `Error: UPGRADE FAILED: "traefik" has no deployed releases`
- **Why it happened:** In your first successful command, you explicitly told Helm where Traefik lives by adding `--namespace traefik`. In your second command, you left that flag off. When Helm doesn't see a namespace flag, it assumes you mean the default namespace. Since Traefik isn't in default, Helm throws its hands up and says "I don't see a release here!"
- **The Fix:** Simply add the `--namespace traefik` (or `-n traefik`) flag back to your command.

### 2. The TLS Secret Error
- **The Error:** `ERR Error configuring TLS error="secret default/argocd-server-tls does not exist"`
- **Why it happened:** In standard Kubernetes, when you include the `tls:` block in your Ingress file, Kubernetes expects you to provide a `secretName` containing your actual SSL certificates. Because you are routing to `argocd.localhost`, you likely don't have a real, signed SSL certificate stored in a Kubernetes Secret yet. Traefik is trying to find that secret to serve the HTTPS connection, failing to find it, and throwing an error.
- **The Fix:** Since this is a local development environment (`.localhost`), you can just rely on Traefik's built-in default self-signed certificate. You don't need the `tls:` block at all because the annotation `traefik.ingress.kubernetes.io/router.tls: "true"` is enough to tell Traefik to serve it securely.

Go back into your Argo CD `values.yaml` (and do the same for Jenkins if it has the same block) and completely remove the `tls:` section.

Change it from this:
```yaml
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/router.tls: "true"
    hostname: argocd.localhost 
    tls:               # <--- REMOVE THIS
      - hosts:         # <--- REMOVE THIS
          - argocd.localhost # <--- REMOVE THIS
```
To exactly this:
```yaml
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/router.tls: "true"
    hostname: argocd.localhost
```

### -------------ISSUES WITH service and internal server error for 8443---

**The Final Boss: The h2c Protocol**
Argo CD is a very unique application because it serves a Web UI (standard HTTP) and a command-line tool (gRPC) on the exact same port.

When we told Argo CD to turn off its internal HTTPS (`server.insecure: true`), Argo CD had to switch to a special protocol called `h2c` (HTTP/2 Cleartext) so it could continue to handle both web traffic and CLI traffic simultaneously without encryption.

Right now, Traefik is going to Argo CD's door and trying to speak standard HTTP/1.1. Argo CD only understands `h2c`. Traefik gets confused by the language barrier, gives up, and throws a 500 Internal Server Error.

**The Fix: Tell Traefik to speak h2c**
We just need to add one single annotation to tell Traefik what language to speak to the backend.

### Ports Reference
- **https build ->** 8443 port
- **http ->** 8080 port
- both jenkins & argocd

**INFO for http:**
- Container Port: 8000 (This is Traefik's web door where your ingress rules actually live)
- Local Port: 8080 (This is the port you want to type into your browser on your laptop)

### ---specifically for argocdServerAdminPassword and Mtime--------

**What is mtime and Its Purpose?**
`mtime` stands for modification time. In the context of ArgoCD, it is simply a timestamp that tells the system exactly when the administrator password was last changed.

Its primary purpose is security and session management.

ArgoCD uses stateless JWTs (JSON Web Tokens) for user sessions. Instead of keeping a heavy database of every logged-in user, ArgoCD simply hands your browser a cryptographically signed token when you log in. That token contains the exact time it was issued.

To ensure that old sessions are invalidated when a password is changed (for instance, if an admin leaves the company or a password is compromised), ArgoCD does a simple math check on every single request:

- Valid Session: `Token Issued Time > Password mtime`
- Invalid Session: `Token Issued Time < Password mtime`

If ArgoCD sees a token that was issued before the password's `mtime`, it assumes the password was reset after that user logged in, and it instantly revokes their access.

*Also note server adminpassword is in bcrypt hash form.*