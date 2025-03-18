#!/bin/bash

#email alerts
sparkpostmail() {
  JSON=$(sed "s/##SUBJECT##/$1/" ~/.aiemon/mail.json |sed "s/##BODY##/$2/")
  curl -X POST "https://api.sparkpost.com/api/v1/transmissions" -H "Authorization: $SPARKPOSTAPIKEY" -H "Content-Type: application/json" -d "$JSON"
}

#check kubernetes resources
#if 'requests' of cpu, memory or ephemeral storage on any node in the workload cluster > 90% then return a DOWN state
check_kubernetes_resources() {
  KUBERESOURCES_NOW="UP"
  for requestpercentage in $(kubectl describe nodes |grep -A4 'Resource                   Requests         Limits'|grep %|awk '{print $3}'|grep -oP '\(\K[^%]+')
  do 
    if [ $requestpercentage -ge 90 ]; then KUBERESOURCES_NOW="DOWN";fi
  done
}


#the file that contains results of previous check cycle
STATUSFILE=~/.aiemon/status
#current date and time
now=$(date "+%Y-%m-%d %H:%M:%S")

#determine identity of this pcai from local kubeconfig
CLUSTERNAME=$(cat ~/.kube/config |grep '    cluster:'|awk '{print $2}')

if [ -z "${CLUSTERNAME}" ];then
  echo "Unable to determine cluster name from ~/.kube/config, please check kubeconfig is in place and is readable by $USER."
  echo "Exiting.."
  exit 1
fi

echo "Running status checks for $CLUSTERNAME at $now"

#read the previous status of each check or set UNKNOWN
KUBEAPI_PREV=$(cat $STATUSFILE|grep KUBEAPI|awk '{print $2}'); if [ -z $KUBEAPI_PREV ]; then KUBEAPI_PREV="UNKNOWN";fi
KUBENODES_PREV=$(cat $STATUSFILE|grep KUBENODES|awk '{print $2}'); if [ -z $KUBENODES_PREV ]; then KUBENODES_PREV="UNKNOWN";fi
WEBUI_PREV=$(cat $STATUSFILE|grep WEBUI|awk '{print $2}'); if [ -z $WEBUI_PREV ]; then WEBUI_PREV="UNKNOWN";fi
KUBERESOURCES_PREV=$(cat $STATUSFILE|grep KUBERESOURCES|awk '{print $2}'); if [ -z $KUBERESOURCES_PREV ]; then KUBERESOURCES_PREV="UNKNOWN";fi

#Check 1: get the homepage URL using a kubeapi request
AIEHOME=$(kubectl --request-timeout=5s -n ui get virtualservice ezaf-ui-vs -o jsonpath="{.spec.hosts[]}")

if [ $? -ne 0 ]; then
  KUBEAPI_NOW="DOWN"
else
  KUBEAPI_NOW="UP"
fi

#send alert if there was a state change
if [ $KUBEAPI_NOW != $KUBEAPI_PREV ]; then
  sparkpostmail "$CLUSTERNAME Kubeapi $KUBEAPI_NOW" "$CLUSTERNAME ALERT $now: Kubeapi has changed from $KUBEAPI_PREV to $KUBEAPI_NOW"
fi

if [ $KUBEAPI_NOW == "UP" ];then

  #Check 2: check the AIE homepage is accessible
  echo "Accessing $AIEHOME at $now"
  WEBSTATUS=$(curl -k -s -o /dev/null -w "%{http_code}" https://$AIEHOME)
  echo "Got a status of $WEBSTATUS"

  if [ $WEBSTATUS -eq 200 ]; then
    WEBUI_NOW="UP"
  else
    WEBUI_NOW="DOWN"
  fi

  #send alert if there was a state change
  if [ $WEBUI_NOW != $WEBUI_PREV ]; then
    sparkpostmail "$CLUSTERNAME Web UI $WEBUI_NOW" "$CLUSTERNAME ALERT $now: Web interface has changed from $WEBUI_PREV to $WEBUI_NOW"
  fi

  #Check 3: check for any nodes that are NotReady
  NODES_NOT_READY=$(kubectl get nodes | tail -n+2 | grep NotReady |wc -l)
  if [ $NODES_NOT_READY -eq 0 ]; then
    KUBENODES_NOW="UP"
  else
    KUBENODES_NOW="DOWN"
  fi

  #send alert if there was a state change
  if [ $KUBENODES_NOW != $KUBENODES_PREV ]; then
    sparkpostmail "$CLUSTERNAME Kubernetes Nodes $KUBENODES_NOW" "$CLUSTERNAME ALERT $now: Kubernetes node state has changed from $KUBENODES_PREV to $KUBENODES_NOW"
  fi
  
  #Check 4: see if any resource requests exceeds 90%
  check_kubernetes_resources
  #send alert if there was a state change
  if [ $KUBERESOURCES__NOW != $KUBERESOURCES_PREV ]; then
    sparkpostmail "$CLUSTERNAME Kubernetes Resources $KUBERESOURCES__NOW" "$CLUSTERNAME ALERT $now: Kubernetes resource requests on one or more nodes have changed from $KUBERESOURCES_PREV to $KUBERESOURCES_NOW"
  fi
  
fi

#update status file with current statuses
echo "KUBEAPI $KUBEAPI_NOW" > ~/.aiemon/status
echo "KUBENODES $KUBENODES_NOW" >> ~/.aiemon/status
echo "WEBUI $WEBUI_NOW" >> ~/.aiemon/status
echo "KUBERESOURCES $KUBERESOURCES_NOW" >> ~/.aiemon/status
