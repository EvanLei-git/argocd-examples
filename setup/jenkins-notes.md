helm repo add jenkins https://charts.jenkins.io
helm repo update

helm install my-jenkins jenkins/jenkins -f jenkins-values.yaml



all changable info:
 helm show values jenkins/jenkins

what ever is inside that values file:
 helm get values my-jenkin


 helm upgrade my-jenkins jenkins/jenkins -f jenkins-values.yaml





==== IMPORTANT =========
tried placing my username and password in the values file, run the  helm upgrade my-jenkins jenkins/jenkins -f jenkins-values.yaml

BUT according to google:
The password you see in /run/secrets/additional/chart-admin-password is what the Helm chart wants the password to be, but Jenkins only reads this value during its very first boot. After that, it stores the password in an internal database that doesn't look at that file anymore. 

tried to chagne the password

kubectl exec -it my-jenkins-0  -- sed -i 's/<useSecurity>
true<\/useSecurity>/<useSecurity>false<\/useSecurity>/' /var/jenkins_home/config.xml
Defaulted container "jenkins" out of: jenkins, config-reload, config-reload-init (init), init (init)

so then i run this

kubectl exec -it my-jenkins-0 -c jenkins -- sed -i 's/<useSecurity>true<\/useSecurity>/<useSecurity>false<\/useSecurity>/' /var/jenkins_home/config.xml












########notes#########

why use

-> serviceType: ClusterIP
  instead of 
-> servicePort: 8080
-> serviceType: NodePort


gemini output:
1. ClusterIP (The "Internal Only" Approach)
ClusterIP is the default Service type in Kubernetes.

What it does: It assigns a private, internal IP address to your application (like Argo CD or Jenkins).

Who can access it: Only other apps and services running inside the exact same Kubernetes cluster. It is completely blocked off from the outside world.

Analogy: It’s like an internal office phone extension. Someone sitting at a desk inside the building can call it, but someone outside the building cannot dial it directly.

2. NodePort (The "Direct Public Door" Approach)
NodePort builds on top of ClusterIP to make the app accessible from the outside.

What it does: It takes your app and exposes it on a specific port (usually a high number between 30000 and 32767) on the actual IP address of the machine (the Node) running your cluster.

Who can access it: Anyone who knows the IP address of your Kubernetes node and that specific high-numbered port (e.g., http://<Node-IP>:31456).

Analogy: It’s like giving your office desk a direct outside phone line. Anyone in the world can call you directly if they know the exact 10-digit number.

3. What about servicePort: 8080?
The servicePort (often just called port in raw Kubernetes manifests) is the port that the Service itself listens on internally to route traffic to your application container.

Whether you use ClusterIP or NodePort, the servicePort: 8080 remains the same. It just means, "Once traffic reaches this Service, send it to port 8080."

Why I recommended changing to ClusterIP
In your previous setup, you are using Nginx Ingress.

Think of an Ingress Controller as a highly intelligent receptionist at the front door of your office building. The receptionist handles all the outside traffic coming in on standard ports (like HTTP on port 80, and HTTPS on port 443).

With NodePort: You are opening random "back doors" (ports 30000+) on your servers. It bypasses the Ingress receptionist completely if someone hits that port. This is usually considered a bad security practice for production, and it's annoying to remember random port numbers.

With ClusterIP + Ingress: You lock all the doors and force everyone to go through the Ingress receptionist. The Ingress controller looks at the request (e.g., "Ah, they want jenkins.localhost") and then routes the traffic internally to Jenkins' private ClusterIP.