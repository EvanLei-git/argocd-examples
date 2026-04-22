# Jenkins Setup & Notes

## Setup Commands

Run these commands in order to completely install and configure Jenkins:

```bash
# 1. Add and update the Jenkins Helm repository
helm repo add jenkins https://charts.jenkins.io
helm repo update

# 2. Install Jenkins using the values file
helm install test-jenkins jenkins/jenkins --namespace jenkins --create-namespace --values jenkins-values.yaml

# 3. Upgrade Jenkins (when modifying jenkins-values.yaml)
helm upgrade my-jenkins jenkins/jenkins -f jenkins-values.yaml --namespace jenkins
```

## Debugging Information & Notes

### Inspecting Configurations
- **View all changeable info:**
  ```bash
  helm show values jenkins/jenkins
  ```
- **View whatever is inside that values file for your release:**
  ```bash
  helm get values my-jenkins
  ```

### Password Issues
==== IMPORTANT =========
Tried placing my username and password in the values file, run the `helm upgrade my-jenkins jenkins/jenkins -f jenkins-values.yaml --namespace jenkins`

BUT according to google:
> The password you see in `/run/secrets/additional/chart-admin-password` is what the Helm chart wants the password to be, but Jenkins only reads this value during its very first boot. After that, it stores the password in an internal database that doesn't look at that file anymore. 

Tried to change the password:
```bash
kubectl exec -it my-jenkins-0 -n jenkins -- sed -i 's/<useSecurity>\ntrue<\/useSecurity>/<useSecurity>false<\/useSecurity>/' /var/jenkins_home/config.xml
```
*Output:* `Defaulted container "jenkins" out of: jenkins, config-reload, config-reload-init (init), init (init)`

So then I ran this (which specifies the container `-c jenkins`):
```bash
kubectl exec -it my-jenkins-0 -n jenkins -c jenkins -- sed -i 's/<useSecurity>true<\/useSecurity>/<useSecurity>false<\/useSecurity>/' /var/jenkins_home/config.xml
```

### Why use ClusterIP instead of NodePort?

Why use:
```yaml
serviceType: ClusterIP
```
instead of:
```yaml
servicePort: 8080
serviceType: NodePort
```

**Explanation:**
**1. ClusterIP (The "Internal Only" Approach)**
ClusterIP is the default Service type in Kubernetes.
- **What it does:** It assigns a private, internal IP address to your application (like Argo CD or Jenkins).
- **Who can access it:** Only other apps and services running inside the exact same Kubernetes cluster. It is completely blocked off from the outside world.
- **Analogy:** It’s like an internal office phone extension. Someone sitting at a desk inside the building can call it, but someone outside the building cannot dial it directly.

**2. NodePort (The "Direct Public Door" Approach)**
NodePort builds on top of ClusterIP to make the app accessible from the outside.
- **What it does:** It takes your app and exposes it on a specific port (usually a high number between 30000 and 32767) on the actual IP address of the machine (the Node) running your cluster.
- **Who can access it:** Anyone who knows the IP address of your Kubernetes node and that specific high-numbered port (e.g., http://<Node-IP>:31456).
- **Analogy:** It’s like giving your office desk a direct outside phone line. Anyone in the world can call you directly if they know the exact 10-digit number.

**3. What about `servicePort: 8080`?**
The `servicePort` (often just called `port` in raw Kubernetes manifests) is the port that the Service itself listens on internally to route traffic to your application container. Whether you use `ClusterIP` or `NodePort`, the `servicePort: 8080` remains the same. It just means, "Once traffic reaches this Service, send it to port 8080."

**Why I recommended changing to ClusterIP:**
In your previous setup, you are using Nginx Ingress.

Think of an Ingress Controller as a highly intelligent receptionist at the front door of your office building. The receptionist handles all the outside traffic coming in on standard ports (like HTTP on port 80, and HTTPS on port 443).

- **With NodePort:** You are opening random "back doors" (ports 30000+) on your servers. It bypasses the Ingress receptionist completely if someone hits that port. This is usually considered a bad security practice for production, and it's annoying to remember random port numbers.
- **With ClusterIP + Ingress:** You lock all the doors and force everyone to go through the Ingress receptionist. The Ingress controller looks at the request (e.g., "Ah, they want jenkins.localhost") and then routes the traffic internally to Jenkins' private ClusterIP.