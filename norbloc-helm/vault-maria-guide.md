# Vault + MariaDB Integration Guide

This guide documents every step taken to integrate HashiCorp Vault with the
`norbloc-helm` MariaDB deployment — covering concepts, commands run, and the
final YAML-based setup via the Vault Secrets Operator (VSO).

---

## Table of Contents

1. [Concepts — What Is a Vault Policy?](#concepts--what-is-a-vault-policy)
2. [Concepts — What Is the Kubernetes Auth Role?](#concepts--what-is-the-kubernetes-auth-role)
3. [Concepts — What Is VSO?](#concepts--what-is-vso-vault-secrets-operator)
4. [Secret Flow Diagram](#secret-flow-diagram)
5. [Step-by-Step: What We Did](#step-by-step-what-we-did)
6. [VSO YAML Files](#vso-yaml-files)
7. [Apply and Verify](#apply-and-verify)
8. [Troubleshooting](#troubleshooting)

---

## Concepts — What Is a Vault Policy?

A Vault Policy is like a Kubernetes RBAC **`Role`** — it is a permission document
**stored inside Vault** that says which secret paths are readable/writable.

```hcl
path "secret/data/mariadb/production" {
  capabilities = ["read"]
}
path "secret/data/mariadb/staging" {
  capabilities = ["read"]
}
```

**Where does it live?** Inside Vault only. It is NOT a Kubernetes resource.

**Can it be a YAML file?** Not directly. It must be created via:
- Vault UI → **Policies** → **ACL Policies** → **Create ACL policy**
- `vault policy write <name>` CLI (run inside the Vault pod)
- Baked into the Vault Helm chart `server.extraConfig` (advanced)

---

## Concepts — What Is the Kubernetes Auth Role?

The Kubernetes Auth Role is like a Kubernetes **`RoleBinding`** — it connects
a ServiceAccount in a specific namespace to a Vault policy.

```
ServiceAccount "default" in namespace "wordpress"
        ↓  presents its JWT token to Vault
Vault checks the role "norbloc-mariadb"
        ↓  role says: use policy "norbloc-mariadb"
Policy grants read on secret/data/mariadb/production + staging
```

**Can it be a YAML file?** YES — via the **Vault Secrets Operator (VSO)** `VaultAuth` CRD.

---

## Concepts — What Is VSO (Vault Secrets Operator)?

VSO is already installed in the cluster (`vault-secrets-operator-system` namespace).
It provides Kubernetes CRDs that let you define Vault integration entirely in YAML:

| CRD | Purpose |
|---|---|
| `VaultConnection` | Points to the Vault server URL |
| `VaultAuth` | Defines how pods authenticate to Vault (replaces the CLI role) |
| `VaultStaticSecret` | Syncs a Vault KV secret into a Kubernetes `Secret` object |

---

## Secret Flow Diagram

```
Vault KV store (KV v2, mounted at "secret/")
  └── mariadb/
      ├── production  { rootPassword, userPassword }
      └── staging     { rootPassword, userPassword }
              │
              │  VaultStaticSecret (CRD — pure YAML, refreshes every 30s)
              ▼
  Kubernetes Secret "norbloc-prod-norbloc-helm-mariadb-credentials"
  Kubernetes Secret "norbloc-staging-norbloc-helm-mariadb-credentials"
              │
              │  secretKeyRef in MariaDB Deployment (already in the chart)
              ▼
  MariaDB pod
    MARIADB_ROOT_PASSWORD ← MYSQL_ROOT_PASSWORD from the K8s Secret
    MARIADB_PASSWORD      ← MYSQL_PASSWORD from the K8s Secret
```

---

## Step-by-Step: What We Did

### 1. Verified Vault is running

```bash
kubectl get pods -A | grep vault
```

Confirmed:
- `vault-0` — Vault server, Running, unsealed
- `vault-agent-injector-*` — Vault Agent Injector, Running
- `vault-secrets-operator-controller-manager-*` — VSO, Running
- Kubernetes auth method already enabled at `kubernetes/`

---

### 2. Checked existing KV structure

```bash
kubectl exec -n vault vault-0 -- vault secrets list
kubectl exec -n vault vault-0 -- vault list secret/metadata/
```

Found KV v2 at `secret/` with:
- `secret/mariadb` — old flat secret (had `MYSQL_PASSWORD`, `WORDPRESS_DB_PASSWORD`)
- `secret/myapp/database` — leftover test secret

---

### 3. Created production and staging secrets — Vault UI (manual, one-time)

1. Open `http://localhost:8200/ui` (port-forward already running on 8200)
2. Log in with your root token
3. Go to **Secrets** → **secret** → **Create secret**

**Created `mariadb/production`:**

| Key | Value |
|---|---|
| `rootPassword` | your strong prod root password |
| `userPassword` | your strong prod WordPress user password |

**Created `mariadb/staging`:**

| Key | Value |
|---|---|
| `rootPassword` | your staging root password |
| `userPassword` | your staging WordPress user password |

> Always use **different** passwords per environment. Prod credentials must be stronger.

---

### 4. Cleaned up old secrets

```bash
# Delete old flat mariadb secret (all versions + metadata)
kubectl exec -n vault vault-0 -- vault kv metadata delete secret/mariadb

# Delete myapp/database (all versions + metadata)
kubectl exec -n vault vault-0 -- vault kv metadata delete secret/myapp/database
```

Verified final Vault structure:

```bash
kubectl exec -n vault vault-0 -- vault list secret/metadata/
# Keys: mariadb/

kubectl exec -n vault vault-0 -- vault list secret/metadata/mariadb/
# Keys: production  staging
```

---

### 5. Created the Vault policy (one-time, via CLI or UI)

**Via CLI:**
```bash
kubectl exec -n vault vault-0 -- /bin/sh -c 'vault policy write norbloc-mariadb - <<EOF
path "secret/data/mariadb/production" {
  capabilities = ["read"]
}
path "secret/data/mariadb/staging" {
  capabilities = ["read"]
}
EOF'
```

**Via Vault UI:**
1. Go to **Policies** → **ACL Policies** → **Create ACL policy**
2. Name: `norbloc-mariadb`
3. Paste the HCL above → **Save**

---

### 6. Registered the Kubernetes auth role (one-time, via CLI)

This is the one command that still needs to run in Vault directly.
After this, all future management is via the `VaultAuth` YAML CRD.

```bash
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/norbloc-mariadb \
  bound_service_account_names="default" \
  bound_service_account_namespaces="wordpress" \
  policies="norbloc-mariadb" \
  ttl="1h"
```

---

## VSO YAML Files

All three files live in `norbloc-helm/vault/`. Apply them once and VSO handles
syncing Vault secrets into Kubernetes Secrets automatically.

### `vault/vault-connection.yaml`
Points VSO at the in-cluster Vault server.

### `vault/vault-auth.yaml`
Tells VSO which Kubernetes role to use when authenticating to Vault.

### `vault/prod-static-secret.yaml`
Syncs `secret/mariadb/production` → K8s Secret `norbloc-norbloc-helm-mariadb-credentials`
(Used by both wp-prod and wp-staging databases in the single shared MariaDB instance)

---

## Apply and Verify

```bash
# Apply all VSO resources
kubectl apply -f vault/

# Check VSO synced the secrets
kubectl get vaultstaticsecret -n wordpress
kubectl get secret norbloc-norbloc-helm-mariadb-credentials -n wordpress

# Verify the password was injected (should print your prod root password)
kubectl get secret norbloc-norbloc-helm-mariadb-credentials -n wordpress \
  -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d

# Restart MariaDB pods so they pick up the newly synced secrets
kubectl rollout restart deployment -n wordpress

# Watch pods recover
kubectl get pods -n wordpress -w
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| MariaDB `CrashLoopBackOff` — "password not specified" | K8s Secret is empty or missing | Check `VaultStaticSecret` status: `kubectl describe vaultstaticsecret -n wordpress` |
| `VaultStaticSecret` in `Pending` | Role not registered in Vault | Run Step 6 CLI command above |
| `403 permission denied` from Vault | Policy path wrong or not bound | `kubectl exec -n vault vault-0 -- vault policy read norbloc-mariadb` |
| Helm upgrade overwrites VSO-synced Secret | `secret.yaml` template re-renders empty secret | Add annotation `helm.sh/resource-policy: keep` to `templates/secret.yaml` |
| VSO not syncing after secret update in Vault | `refreshAfter` window not elapsed | Force sync: `kubectl annotate vaultstaticsecret mariadb-prod-creds -n wordpress force-sync=$(date +%s) --overwrite` |



here are two databases inside the single MariaDB pod. The init configmap runs this SQL on first start:

sql
CREATE DATABASE IF NOT EXISTS `wp-prod-db`;
GRANT ALL PRIVILEGES ON `wp-prod-db`.* TO 'wordpress'@'%';
CREATE DATABASE IF NOT EXISTS `wp-staging-db`;
GRANT ALL PRIVILEGES ON `wp-staging-db`.* TO 'wordpress'@'%';
But here's the current problem: since you scoped environments per release, each MariaDB pod only creates its own database:

norbloc-prod MariaDB → only creates wp-prod-db
norbloc-staging MariaDB → only creates wp-staging-db
So you actually have two separate MariaDB pods, each with their own database and their own PVC. They don't share storage.

How each WordPress knows which database to use:

From wordpress-deployment.yaml line 51:

yaml
- name: WORDPRESS_DB_NAME
  value: {{ $envConfig.database | quote }}   # ← comes from values.environments.wp-prod.database
wp-prod WordPress → WORDPRESS_DB_NAME=wp-prod-db
wp-staging WordPress → WORDPRESS_DB_NAME=wp-staging-db
How to access each database:

bash
# Access prod MariaDB
kubectl exec -it -n wordpress \
  $(kubectl get pod -n wordpress -l app.kubernetes.io/component=mariadb,app.kubernetes.io/managed-by=Helm,helm.sh/chart=norbloc-helm-0.1.0 -o jsonpath='{.items[0].name}' | grep prod) \
  -- mariadb -u root -p
# Simpler — exec directly by pod name prefix
kubectl exec -it -n wordpress \
  $(kubectl get pods -n wordpress --no-headers | grep "norbloc-prod.*mariadb" | awk '{print $1}') \
  -- mariadb -u root -p"prod-root-password"
# Access staging MariaDB
kubectl exec -it -n wordpress \
  $(kubectl get pods -n wordpress --no-headers | grep "norbloc-staging.*mariadb" | awk '{print $1}') \
  -- mariadb -u root -p"staging-root-password"
# List databases once inside
SHOW DATABASES;
Question 2 — Changing the Vault password
This is the critical gotcha: changing the Vault secret does NOT automatically update the password inside MariaDB.

Here's why — there are two separate concepts of "password":

Vault secret           K8s Secret             MariaDB internal DB
rootPassword: "new" → MYSQL_ROOT_PASSWORD  → DOES NOT auto-update
                       (VSO syncs this)       MariaDB stores its own
                                              user table with a HASH
                                              of the original password
Layer	What changes automatically	What does NOT
Vault → K8s Secret	✅ VSO syncs within 30s	—
K8s Secret → Pod env var	✅ On pod restart	Not live — needs restart
Pod env var → MariaDB internal user	❌ Never automatic	Must ALTER USER in SQL
So the correct procedure to rotate a password is:

bash
# Step 1 — Update password in Vault UI (or CLI)
# (VSO will sync to K8s Secret within 30s)
# Step 2 — Update the password inside MariaDB itself
kubectl exec -it -n wordpress \
  $(kubectl get pods -n wordpress --no-headers | grep "norbloc-prod.*mariadb" | awk '{print $1}') \
  -- mariadb -u root -p"OLD-root-password" \
  -e "ALTER USER 'root'@'%' IDENTIFIED BY 'NEW-root-password'; ALTER USER 'wordpress'@'%' IDENTIFIED BY 'NEW-wp-password'; FLUSH PRIVILEGES;"
# Step 3 — Restart pods so they read the new K8s Secret value
kubectl rollout restart deployment -n wordpress \
  $(kubectl get deploy -n wordpress --no-headers | grep prod | awk '{print $1}')
Bottom line: Vault rotation keeps the K8s Secret in sync automatically, but MariaDB's internal user table is a separate database that must be updated with ALTER USER. They are not linked.