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
