#!/bin/sh
#
# Integrate CLVM and DLM Pacemaker resource.
#
# Pacemaker ordering resource constraints:
# Start & Promote DRBD then start DLM then start CLVM then start GFS2
#

#set -x
set -e

alias echo='echo [$HOSTNAME] '

echo ""
echo "##################### CLVM+DLM Pacemaker Integration ##################"

pcs resource create dlm ocf:pacemaker:controld op monitor interval=60s
pcs resource clone dlm clone-max=2 clone-node-max=1 interleave=true ordered=true
pcs resource create clvmd ocf:heartbeat:clvm op monitor interval=60s
pcs resource clone clvmd clone-max=2 clone-node-max=1 interleave=true ordered=true

echo "Integrated CLVM and DLM cloned resources into Pacemaker"
logger "Integrated CLVM and DLM cloned resources into Pacemaker"

