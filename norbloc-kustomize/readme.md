# Kustomize + Vault Secret Synchronization Guide

This document outlines the steps taken to integrate HashiCorp Vault with the `norbloc-kustomize` deployment. It explains how credentials flow from Vault into Kubernetes so the MariaDB and WordPress pods can start securely without hardcoded passwords.

## 1. Creating the Secret in Vault

We created a secret in Vault at the path `secret/mariadb` containing the database passwords. Because the Vault keys exactly match the environment variables expected by the pods (`MYSQL_ROOT_PASSWORD` and `MYSQL_PASSWORD`), we do not need a translation block in the VSO sync file.

**Command:**
```bash
kubectl exec -n vault vault-0 -- vault kv put secret/mariadb \
  MYSQL_ROOT_PASSWORD=<paste-ur-password> \
  MYSQL_PASSWORD=<paste-ur-password>
```

## 2. Creating the Vault Policy

Vault KV-v2 secrets require read access to both the data and metadata paths. We created a policy named `db-secrets-policy` to explicitly grant the Vault Secrets Operator (VSO) permission to read this specific secret.

**Command:**
```bash
cat <<EOF | kubectl exec -i -n vault vault-0 -- vault policy write db-secrets-policy -
path "secret/data/mariadb" {
  capabilities = ["read", "list"]
}
path "secret/metadata/mariadb" {
  capabilities = ["read", "list"]
}
EOF
```

## 3. Creating the Kubernetes Auth Role

We linked the Kubernetes `default` Service Account (in the `wordpress` namespace) to the `db-secrets-policy` inside Vault by creating an auth role named `db-secrets-role`.

**Command:**
```bash
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/db-secrets-role \
  bound_service_account_names="default" \
  bound_service_account_namespaces="wordpress" \
  policies="db-secrets-policy" \
  ttl="1h"
```

secret/data/mariadb: This is where the actual payload lives (your MYSQL_PASSWORD and MYSQL_ROOT_PASSWORD). The operator needs to read this path to get the actual text to inject into Kubernetes.

secret/metadata/mariadb: Because KV-v2 supports versioning (it remembers old passwords if you change them), Vault stores the version history, creation dates, and deletion status in a separate metadata path. The Vault Secrets Operator (VSO) always queries this metadata path first to figure out what the latest version of your secret is before it attempts to download the data.

If you only give it the data path, VSO gets a 403 Permission Denied when it tries to check the version history, and it completely aborts the sync. (In fact, missing the metadata path is exactly why your pods were stuck in CreateContainerConfigError earlier today!)

## How the Architecture Works

1. **Deployment (`kustomize build`)**: You apply your Kustomize overlays, which include the `VaultStaticSecret` (defined in `vault-secret-sync.yaml`) and the `VaultAuth` (`vault-auth-config.yaml`).
2. **Authentication**: The Vault Secrets Operator (VSO) reads the `VaultAuth` config and attempts to log in to Vault using the `db-secrets-role`.
3. **Authorization**: Vault verifies the Kubernetes Service Account, checks the role, and attaches the `db-secrets-policy`.
4. **Synchronization**: VSO pulls the keys from `secret/mariadb` (because the policy allows it) and automatically generates a native Kubernetes Secret named `mariadb-credentials`.
5. **Pod Startup**: Your `mariadb-deployment` and `wordpress-deployment` pods, which were waiting in a `CreateContainerConfigError` state, detect the new `mariadb-credentials` secret, inject the passwords as environment variables, and successfully start running.
