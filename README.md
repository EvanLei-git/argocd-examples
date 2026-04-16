# argocd-examples


helm search repo bitnami/redis --versions

# MY NOTES

inside dev:
kustomize build . --enable-helm | kubectl apply -f -

notes to self for logs since k9s didnt show anything:
kubectl describe pod -l app.kubernetes.io/name=postgresql -n dev-env