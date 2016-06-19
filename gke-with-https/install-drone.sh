#!/usr/bin/env bash
kubectl cluster-info > /dev/null 2>&1
if [ $? -eq 1 ]
then
  echo "kubectl was unable to reach your Kubernetes cluster. Make sure that" \
       "you have selected one using the 'gcloud container' commands."
  exit 1
fi

# If secrets.yaml isn't present, we'll auto-generate the Drone secret and
# upload it via kubectl.
if ! [ -f "secrets.yaml" ];
then
    echo "secrets.yaml not present. Randomly generating and uploading..."
    drone_token=`cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`
    b64_drone_token=`echo $drone_token | base64`
    sed "s/REPLACE-THIS-WITH-BASE64-ENCODED-VALUE/${b64_drone_token}/g" .secrets.yaml.tpl > secrets.yaml
    kubectl create -f secrets.yaml
fi

# Clear out the old values, since we're being crude.
kubectl delete configmap drone 2> /dev/null
if [ $? -eq 1 ]
then
  echo "Before continuing, make sure you've opened drone-configmap.yaml and" \
       "changed the values prefixed with CHANGEME in the comments."
  echo
  read -p "<Press enter once you've made your edits>"
fi

kubectl create -f drone-server-svc.yaml 2> /dev/null
if [ $? -eq 0 ]
then
  echo "Since this is your first time running this script, we just created a" \
       "front-facing Load Balancer with an external IP. You'll need to wait" \
       "for the LB to initialize and pull an IP address. We'll pause for a" \
       "bit and walk you through this after the break."
  while true; do
    echo "Waiting for 60 seconds for LB creation..."
    sleep 60
    echo "[[ Querying your drone-server service to see if it has an IP yet... ]]"
    echo
    kubectl describe svc drone-server
    echo "[[ Query complete. ]]"
    read -p "Do you see a value above for 'Loadbalancer Ingress'? (y/n) " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) echo "We'll give it some more time.";;
        * ) echo "No idea what that was, but we'll assume yes!";;
    esac
  done
  echo
  echo "Excellent. Create a DNS (A) Record that matches the value you entered" \
       "for proxy.fqdn in drone-configmap.yaml. It should point at the IP you" \
       "see above next to 'Loadbalancer Ingress'. Once you have configured the" \
       "DNS entry, don't proceed until nslookup is showing the IP you set." \
       "Let's Encrypt needs to be able to resolve and send a request to your " \
       "server in order to verify service and generate the cert."
  read -p "<Press enter to proceed once nslookup is resolving your proxy FQDN>"
fi

kubectl delete rc drone-server 2> /dev/null
kubectl create -f drone-configmap.yaml
kubectl create -f drone-server-rc.yaml
echo
echo "===== Drone Server installed ============================================"
echo "You should now have a running Drone Server. Point your browser"
echo "at https://<your-fqdn-here> and you should see a login page."
echo
read -p "<Press enter once you've verified that your Drone Server is up>"
echo
echo "===== Drone Agent installation =========================================="
kubectl delete rc drone-agent 2> /dev/null
kubectl create -f drone-agent-rc.yaml
echo
echo "===== Post-installation tasks ==========================================="
echo "At this point, you should have a fully-functional Drone install. If this"
echo "Is not the case, stop by either of the following for help:"
echo
echo "  * Gitter (realtime chat): https://gitter.im/drone/drone"
echo "  * Discussion Site, help category: https://discuss.drone.io/c/help"
