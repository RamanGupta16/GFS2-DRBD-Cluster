#!/bin/sh
#
# Pacemaker ordering resource constraints:
# Start & Promote DRBD then start DLM then start CLVM then start GFS2
#

#set -e

alias echo='echo [$HOSTNAME] '

DRBD_RESOURCE_NAME=vDrbd

echo "############### Pacemaker ordering and colocation constraints #########"

sleep 5

# Wait till both DRBD become Primary
DRBD_CXN_STATE="`drbdadm role ${DRBD_RESOURCE_NAME}`"
while [ ${LOCAL_DRBD_CXN_STATE} != "Primary/Primary" ]
do
  sleep 5
  DRBD_CXN_STATE="`drbdadm role ${DRBD_RESOURCE_NAME}`"
done

echo "Both nodes DRBD connection state: ${DRBD_CXN_STATE}"

logger "Adding Pacemaker constraints since both nodes cxn state ${DRBD_CXN_STATE}"

pcs cluster cib cstr_cfg

pcs -f cstr_cfg constraint order promote drbd_data_clone then start dlm-clone
pcs -f cstr_cfg constraint order start dlm-clone then start clvmd-clone
pcs -f cstr_cfg constraint order start clvmd-clone then start Gfs2FS-clone

pcs -f cstr_cfg constraint colocation add dlm-clone with drbd_data_clone 
pcs -f cstr_cfg constraint colocation add clvmd-clone with dlm-clone
pcs -f cstr_cfg constraint colocation add Gfs2FS-clone with clvmd-clone

pcs cluster cib-push cstr_cfg
logger "Added Pacemaker constraints"

