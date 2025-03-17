#!/bin/bash

#emailing function
sparkpostmail() {
  JSON=$(sed "s/##SUBJECT##/$1/" ~/.aiemon/mail.json |sed "s/##BODY##/$2/")
  curl -X POST "https://api.sparkpost.com/api/v1/transmissions" -H "Authorization: $SPARKPOSTAPIKEY" -H "Content-Type: application/json" -d "$JSON"
}


#the file that contains results of previous check cycle
STATUSFILE=~/.aiemon/status
now=$(date "+%Y-%m-%d %H:%M:%S")

#determine identify of this pcai from local kubeconfig
CLUSTERNAME=$(cat ~/.kube/config |grep '    cluster:'|awk '{print $2}')

if [ -z "${CLUSTERNAME}" ];then
  echo "Unable to determine cluster name from ~/.kube/config, please check kubeconfig is in place and is readable by $USER."
  echo "Exiting.."
  exit 1
fi

echo "Running status checks for $CLUSTERNAME at $now"

#read in the previous status of each check or set UNKNOWN
KUBEAPI_PREV=$(cat $STATUSFILE|grep KUBEAPI|awk '{print $2}'); if [ -z $KUBEAPI_PREV ]; then KUBEAPI_PREV="UNKNOWN";fi
KUBENODES_PREV=$(cat $STATUSFILE|grep KUBENODES|awk '{print $2}'); if [ -z $KUBENODES_PREV ]; then KUBENODES_PREV="UNKNOWN";fi
WEBUI_PREV=$(cat $STATUSFILE|grep WEBUI|awk '{print $2}'); if [ -z $WEBUI_PREV ]; then WEBUI_PREV="UNKNOWN";fi

#get the homepage URL
echo "Obtaining homepage details via kubeapi request.."
AIEHOME=$(kubectl --request-timeout=5s -n ui get virtualservice ezaf-ui-vs -o jsonpath="{.spec.hosts[]}")

if [ $? -ne 0 ]; then
  #kubeapi is not accessible
  KUBEAPI_NOW="DOWN"
else
  KUBEAPI_NOW="UP"
fi

#send alert if there was a state change
if [ $KUBEAPI_NOW != $KUBEAPI_PREV ]; then
  sparkpostmail "$CLUSTERNAME Kubeapi $KUBEAPI_NOW" "$CLUSTERNAME ALERT $now: Kubeapi has changed from $KUBEAPI_PREV to $KUBEAPI_NOW"
fi

if [ $KUBEAPI_NOW == "UP" ];then
  #check the web UI is up
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
    #echo "$CLUSTERNAME ALERT $now: Web UI has gone from $WEBUI_PREV to $WEBUI_NOW"
    sparkpostmail "$CLUSTERNAME Web UI $WEBUI_NOW" "$CLUSTERNAME ALERT $now: Web interface has changed from $WEBUI_PREV to $WEBUI_NOW"
  fi

  #check for any nodes that are NotReady
  NODES_NOT_READY=$(kubectl get nodes | tail -n+2 | grep NotReady |wc -l)
  if [ $NODES_NOT_READY -eq 0 ]; then
    KUBENODES_NOW="UP"
  else
    KUBENODES_NOW="DOWN"
  fi

  #send alert if there was a state change
  if [ $KUBENODES_NOW != $KUBENODES_PREV ]; then
    #echo "$CLUSTERNAME ALERT $now: Kubernetes node state has gone from $KUBENODES_PREV to $KUBENODES_NOW"
    sparkpostmail "$CLUSTERNAME Kubernetes Nodes $KUBENODES_NOW" "$CLUSTERNAME ALERT $now: Kubernetes node state has changed from $KUBENODES_PREV to $KUBENODES_NOW"
  fi
fi

#update status file with current statuses
echo "KUBEAPI $KUBEAPI_NOW" > ~/.aiemon/status
echo "KUBENODES $KUBENODES_NOW" >> ~/.aiemon/status
echo "WEBUI $WEBUI_NOW" >> ~/.aiemon/status
