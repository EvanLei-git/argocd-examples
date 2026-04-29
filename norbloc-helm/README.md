# Norbloc Helm Chart

This Helm chart packages the WordPress and MariaDB application for generic deployments to Kubernetes clusters.

## Helm Templating and Conditionals (If/Else) Explained

In some template files in this exact chart (like `ingress.yaml` or `mariadb-pvc.yaml`), you will notice Go templating `{{- if ... }}` and `{{- else }}` blocks. 

Helm introduces logic based on the values provided in `values.yaml` to make the deployment customizable for different environments without having to rewrite YAML files.

Here is an explanation of the conditionals used in this chart:

### 1. Ingress Toggle (`ingress.enabled`)
**Found in:** `templates/ingress.yaml`
```yaml
{{- if .Values.ingress.enabled -}}
```
- **Why it's used:** Sometimes you want to expose your application to the outside world via an Ingress (like in Production at `norbloc.com`), but in other environments (like local development through minikube or KinD), you only want it accessible via port-forwarding or a NodePort.
- **What it does:** If you set `ingress.enabled: true` in your `values.yaml`, Helm will generate the Ingress. If it's `false`, Helm will simply skip compiling `ingress.yaml` entirely.

### 2. Persistence / Storage Allocation (`persistence.enabled`)
**Found in:** `templates/mariadb-pvc.yaml`, `templates/wordpress-pvc.yaml`
```yaml
{{- if .Values.mariadb.persistence.enabled }}
```
**Found in:** `templates/mariadb-deployment.yaml`, `templates/wordpress-deployment.yaml`
```yaml
      volumes:
      - name: wp-storage-wire
        {{- if .Values.wordpress.persistence.enabled }}
        persistentVolumeClaim:
          claimName: {{ include "norbloc-helm.fullname" . }}-wordpress-pvc
        {{- else }}
        emptyDir: {}
        {{- end }}
```
- **Why it's used:** In production, you *always* want your database data and WordPress files backed by permanent storage (Persistent Volume Claims) so data survives Pod restarts. However, when doing automated testing or local spin-ups, you might want a fresh ephemeral environment that cleans itself up automatically.
- **What it does:** By checking if persistence is enabled, Helm decides whether to create a `PersistentVolumeClaim` (PVC) and attach it to the Pod. If `persistence.enabled: false`, it uses `emptyDir: {}` instead, which is temporary storage that dies when the Pod dies.

### 3. Dynamic Storage Classes (`persistence.storageClass`)
**Found in:** `templates/mariadb-pvc.yaml`, `templates/wordpress-pvc.yaml`
```yaml
  {{- if .Values.mariadb.persistence.storageClass }}
  {{- if (eq "-" .Values.mariadb.persistence.storageClass) }}
  storageClassName: ""
  {{- else }}
  storageClassName: "{{ .Values.mariadb.persistence.storageClass }}"
  {{- end }}
  {{- end }}
```
- **Why it's used:** Different cloud providers use different names for storage types (e.g., AWS has `gp2`, Google has `standard`). 
- **What it does:** 
  - If we leave `storageClass` blank (`""`), Kubernetes uses the cluster's default storage class. 
  - If we pass a hyphen (`"-"`), it locks it to an empty string `""` explicitly.
  - If we set the string (e.g. `"standard"`), it specifically requests that type of cloud storage volume to be attached.

## How to use Custom Values

If you want to apply this to production, you can create a file `production-values.yaml` with your custom settings (like your production URL):

```yaml
ingress:
  enabled: true
  hosts:
    - host: norbloc.com
      paths:
        - path: /
          pathType: ImplementationSpecific
```

Then install the chart using that overrides file:
```bash
# Staging
helm install staging ./norbloc-helm -f ./norbloc-helm/envs/staging-values.yaml -n staging --create-namespace

# Production
helm install production ./norbloc-helm -f ./norbloc-helm/envs/production-values.yaml -n production --create-namespace

```
