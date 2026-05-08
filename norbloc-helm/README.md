# norbloc-helm — Deployment & Vault Secrets Guide

A Helm chart that deploys a shared **MariaDB** instance + multi-environment **WordPress** pods
(`wp-prod` and `wp-staging`) into a single Kubernetes namespace.

---

## Table of Contents

1. [Directory Layout](#directory-layout)
2. [Does the `envs/` layout work?](#does-the-envs-layout-work)
3. [Quick-Start (plaintext — local / dev only)](#quick-start-plaintext--local--dev-only)
4. [Vault Integration — Overview](#vault-integration--overview)
5. [Step 1 — Create Vault Keys from the UI](#step-1--create-vault-keys-from-the-ui)
6. [Step 2 — Install & Configure the Vault Agent Injector](#step-2--install--configure-the-vault-agent-injector)
7. [Step 3 — Update the Helm Secret Template](#step-3--update-the-helm-secret-template)
8. [Step 4 — Lift Production Values (Vault)](#step-4--lift-production-values-vault)
9. [Step 5 — Lift Staging Values (Vault)](#step-5--lift-staging-values-vault)
10. [ArgoCD Integration](#argocd-integration)
11. [Troubleshooting](#troubleshooting)

---

## Directory Layout

```
norbloc-helm/
├── Chart.yaml
├── values.yaml                  # base defaults (never store real secrets here)
├── envs/
│   ├── kind-config.yaml         # local Kind cluster config
│   ├── production-values.yaml   # prod-specific overrides
│   └── staging-values.yaml      # staging-specific overrides
├── templates/
│   ├── secret.yaml              # K8s Secret built from values
│   ├── mariadb-deployment.yaml  # MariaDB reads creds from the Secret
│   └── ...
└── jobs/
    └── db-sync-prod-to-staging.yaml
```

---

## Does the `envs/` layout work?

**Yes — with the following caveats:**

| Check | Status | Notes |
|---|---|---|
| `production-values.yaml` overrides `mariadb.auth.*` | ✅ | Merges cleanly over `values.yaml` |
| `staging-values.yaml` overrides `mariadb.auth.*` | ✅ | Merges cleanly over `values.yaml` |
| `secret.yaml` reads `.Values.mariadb.auth.rootPassword` | ✅ | b64-encodes and stores in `MYSQL_ROOT_PASSWORD` |
| `mariadb-deployment.yaml` pulls creds from the Secret | ✅ | Uses `secretKeyRef` — no plaintext in pod spec |
| Plaintext passwords in `envs/*.yaml` | ⚠️ **NOT safe for real clusters** | Replace with Vault (see below) |
| `syncJob.enabled` missing from `staging-values.yaml` | ℹ️ Info | Defaults to `false` in base; add only if needed |

The chart renders correctly today for **local/Kind** testing. Before deploying to a real cluster
you **must** remove the plaintext passwords and pull them from Vault.

---

## Quick-Start (plaintext — local / dev only)

> **Important — working directory matters.**
> Helm needs to find the chart directory. Use whichever option matches where you are.

**Option A — run from _inside_ the `norbloc-helm/` directory (recommended):**

```bash
cd argocd-kustomize-examples/norbloc-helm   # ← chart root, contains Chart.yaml

# 1. Create the Kind cluster
kind create cluster --config envs/kind-config.yaml

# 2. Install for production  (. = current directory = the chart)
helm upgrade --install norbloc-prod . \
  -f envs/production-values.yaml \
  --namespace wordpress --create-namespace

# 3. Install for staging
helm upgrade --install norbloc-staging . \
  -f envs/staging-values.yaml \
  --namespace wordpress
```

**Option B — run from the _parent_ `argocd-kustomize-examples/` directory:**

```bash
cd argocd-kustomize-examples   # ← parent of the chart

helm upgrade --install norbloc-prod ./norbloc-helm \
  -f norbloc-helm/envs/production-values.yaml \
  --namespace wordpress --create-namespace

helm upgrade --install norbloc-staging ./norbloc-helm \
  -f norbloc-helm/envs/staging-values.yaml \
  --namespace wordpress
```

> **Warning:** The passwords in `envs/*.yaml` are plaintext. They end up in a Kubernetes
> `Secret` (base64-encoded, not encrypted). Use Vault for any real environment.

---

## Vault Integration — Overview

```
Vault KV store
  └── secret/norbloc/production/mariadb   { rootPassword, userPassword }
  └── secret/norbloc/staging/mariadb      { rootPassword, userPassword }
          │
          │  Vault Agent Injector (init-container / sidecar)
          ▼
  Kubernetes Pod
    envs/production-values.yaml  ──► rootPassword: ""   (empty — Vault fills it)
    templates/secret.yaml        ──► reads from Vault-mounted file or env
```

Two integration strategies are available:

| Strategy | How it works | Best for |
|---|---|---|
| **Vault Agent Injector** (annotations) | Sidecar writes secrets to `/vault/secrets/` | Most setups — no app changes |
| **External Secrets Operator (ESO)** | ESO syncs Vault → K8s Secret on a schedule | When you need a native K8s Secret object |

This guide uses the **Vault Agent Injector** (most common with Helm + ArgoCD).

---

## Step 1 — Create Vault Keys from the UI

### 1.1 Log in to the Vault UI

Open `https://<your-vault-address>:8200` in your browser and log in
(Token, LDAP, or OIDC — whichever your cluster uses).

### 1.2 Enable the KV v2 secrets engine (once per cluster)

1. In the left sidebar click **Secrets Engines**.
2. Click **Enable new engine**.
3. Choose **KV** → click **Next**.
4. Set **Path** to `secret` (or your preferred mount, e.g. `norbloc`).
5. Set **Version** to **2**.
6. Click **Enable Engine**.

### 1.3 Create the Production secret

1. Navigate to **Secrets** → `secret/` (your KV mount).
2. Click **Create secret**.
3. Fill in:
   - **Path for this secret**: `norbloc/production/mariadb`
   - Add key-value pairs:

| Key | Value |
|---|---|
| `rootPassword` | `<your-strong-prod-root-password>` |
| `userPassword` | `<your-strong-prod-wp-password>` |

4. Click **Save**.

### 1.4 Create the Staging secret

Repeat the same steps with:

- **Path**: `norbloc/staging/mariadb`

| Key | Value |
|---|---|
| `rootPassword` | `<your-staging-root-password>` |
| `userPassword` | `<your-staging-wp-password>` |

### 1.5 Create a Vault Policy

In the Vault UI:

1. Go to **Policies** → **ACL Policies** → **Create ACL policy**.
2. Name: `norbloc-mariadb-policy`
3. Paste the following HCL:

```hcl
# Allow read on production mariadb secrets
path "secret/data/norbloc/production/mariadb" {
  capabilities = ["read"]
}

# Allow read on staging mariadb secrets
path "secret/data/norbloc/staging/mariadb" {
  capabilities = ["read"]
}
```

4. Click **Save**.

### 1.6 Enable Kubernetes Auth and bind the policy

> If Kubernetes auth is already enabled, skip straight to creating the role.

In the Vault UI:

1. Go to **Access** → **Auth Methods** → **Enable new method**.
2. Choose **Kubernetes** → **Next**.
3. Set mount path to `kubernetes` → **Enable Method**.
4. Configure it (CLI is easiest here):

```bash
vault write auth/kubernetes/config \
  kubernetes_host="https://<KUBE_API_HOST>:443"
```

5. Create a role that binds the policy to the `wordpress` service account:

```bash
vault write auth/kubernetes/role/norbloc-mariadb \
  bound_service_account_names=norbloc-mariadb-sa \
  bound_service_account_namespaces=wordpress \
  policies=norbloc-mariadb-policy \
  ttl=1h
```

---

## Step 2 — Install & Configure the Vault Agent Injector

```bash
# Add HashiCorp repo
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault (injector only — skip server if Vault runs elsewhere)
helm upgrade --install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --set "injector.enabled=true" \
  --set "server.enabled=false" \
  --set "injector.externalVaultAddr=http://<your-vault-address>:8200"
```

Create the `ServiceAccount` used by the pods:

```bash
kubectl create serviceaccount norbloc-mariadb-sa -n wordpress
```

---

## Step 3 — Update the Helm Secret Template

When using Vault injection the `secret.yaml` template is **no longer responsible for the
password values** — Vault writes them directly into the pod via an annotation-driven sidecar.

Replace `templates/secret.yaml` with a version that reads from environment variables that
the Vault sidecar populates, **or** switch to the External Secrets Operator approach to keep
a native `Secret` object (recommended for zero app-code changes).

### Option A — Vault Agent file injection (annotations on the Deployment)

Add these annotations to `templates/mariadb-deployment.yaml` under
`spec.template.metadata.annotations`:

```yaml
# Production example — place equivalent block in the pod spec
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: "norbloc-mariadb"
vault.hashicorp.com/agent-inject-secret-mariadb: "secret/data/norbloc/production/mariadb"
vault.hashicorp.com/agent-inject-template-mariadb: |
  {{- with secret "secret/data/norbloc/production/mariadb" -}}
  export MARIADB_ROOT_PASSWORD="{{ .Data.data.rootPassword }}"
  export MARIADB_PASSWORD="{{ .Data.data.userPassword }}"
  {{- end }}
```

Then in the container command source the file:

```yaml
command: ["/bin/sh", "-c", "source /vault/secrets/mariadb && docker-entrypoint.sh mariadbd"]
```

### Option B — External Secrets Operator (keeps native K8s Secret)

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

Create an `ExternalSecret` resource per environment:

```yaml
# envs/production-external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: norbloc-prod-mariadb-creds
  namespace: wordpress
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: norbloc-prod-mariadb-credentials   # becomes a K8s Secret
    creationPolicy: Owner
  data:
    - secretKey: MYSQL_ROOT_PASSWORD
      remoteRef:
        key: secret/data/norbloc/production/mariadb
        property: rootPassword
    - secretKey: MYSQL_PASSWORD
      remoteRef:
        key: secret/data/norbloc/production/mariadb
        property: userPassword
```

With ESO you **keep** `templates/secret.yaml` but remove the hardcoded values — the Secret
is now owned and refreshed by ESO.

---

## Step 4 — Lift Production Values (Vault)

Update `envs/production-values.yaml` — remove plaintext passwords:

```yaml
# envs/production-values.yaml  (Vault-ready)
mariadb:
  image:
    tag: "11.8"
  persistence:
    size: 10Gi
  auth:
    rootPassword: ""    # injected by Vault — do NOT set here
    userPassword: ""    # injected by Vault — do NOT set here

wordpress:
  image:
    tag: "6.9.4-apache"
  debug: "0"
  persistence:
    size: 5Gi

syncJob:
  enabled: false
```

Deploy production:

```bash
helm upgrade --install norbloc-prod ./norbloc-helm \
  -f envs/production-values.yaml \
  --namespace wordpress --create-namespace \
  --set "mariadb.serviceAccount.name=norbloc-mariadb-sa"
```

Verify the secret was injected:

```bash
kubectl exec -n wordpress deploy/norbloc-prod-norbloc-helm-mariadb \
  -- cat /vault/secrets/mariadb
```

---

## Step 5 — Lift Staging Values (Vault)

Update `envs/staging-values.yaml` — remove plaintext passwords:

```yaml
# envs/staging-values.yaml  (Vault-ready)
mariadb:
  image:
    tag: "11.8"
  persistence:
    size: 2Gi
  auth:
    rootPassword: ""    # injected by Vault — do NOT set here
    userPassword: ""    # injected by Vault — do NOT set here

wordpress:
  image:
    tag: "6.9.4-apache"
  debug: "1"
  persistence:
    size: 2Gi
```

Deploy staging:

```bash
helm upgrade --install norbloc-staging ./norbloc-helm \
  -f envs/staging-values.yaml \
  --namespace wordpress \
  --set "mariadb.serviceAccount.name=norbloc-mariadb-sa"
```

The Vault Agent sidecar reads `secret/data/norbloc/staging/mariadb` (as configured in
the Deployment annotations) and populates the credentials before MariaDB starts.

---

## ArgoCD Integration

When managing these releases through ArgoCD, specify the env-values file in your
`Application` CR's `helm.valueFiles`:

```yaml
# Production ArgoCD Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: norbloc-prod
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/<org>/argocd-kustomize-examples.git
    targetRevision: main
    path: norbloc-helm
    helm:
      valueFiles:
        - envs/production-values.yaml   # path relative to chart root
  destination:
    server: https://kubernetes.default.svc
    namespace: wordpress
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
---
# Staging ArgoCD Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: norbloc-staging
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/<org>/argocd-kustomize-examples.git
    targetRevision: main
    path: norbloc-helm
    helm:
      valueFiles:
        - envs/staging-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: wordpress
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

> **ArgoCD + Vault tip:** ArgoCD does **not** natively call the Vault API. The Vault Agent
> Injector (or ESO) runs inside the cluster and handles secret injection at pod start-up.
> ArgoCD just deploys the chart; Vault handles the secrets.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `MountVolume.SetUp failed` | PVC StorageClass missing | Set `mariadb.persistence.storageClass` in values |
| MariaDB pod `CrashLoopBackOff` | Wrong root password / Vault unreachable | Check `kubectl logs` and `/vault/secrets/mariadb` content |
| Vault sidecar not injecting | Injector not installed or annotation typo | `kubectl describe pod` → check init-container logs |
| `403 permission denied` from Vault | Policy not bound to SA | Verify `vault read auth/kubernetes/role/norbloc-mariadb` |
| `helm upgrade` resets secret | `secret.yaml` still has hardcoded values | Set `auth.rootPassword: ""` and let Vault own the value |
| ESO ExternalSecret `SecretSyncedError` | ClusterSecretStore not configured | `kubectl describe clustersecretstore vault-backend` |
