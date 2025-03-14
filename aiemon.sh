#!/bin/bash
now=$(date "+%Y-%m-%d %H:%M:%S")
echo "Checking $AIEHOME at $now"
status=curl -k -s -o /dev/null -w "%{http_code}" $AIEHOME
echo "Got a status of $status"
