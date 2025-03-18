#!/bin/bash

curl https://raw.githubusercontent.com/abe-hpe/hosted-aie-monitoring/refs/heads/main/aiemon.sh > ~/.aiemon/aiemon.sh
curl https://raw.githubusercontent.com/abe-hpe/hosted-aie-monitoring/refs/heads/main/mail.json > ~/.aiemon/mail.json
chmod a+x ~/.aiemon/aiemon.sh
~/.aiemon/aiemon.sh
