#!/bin/sh
#
# Integrate DRBD as dual-master Pacemaker resource.
#
# Pacemaker ordering resource constraints:
# Start & Promote DRBD then start DLM then start CLVM then start GFS2
#

#set -x
set -e

alias echo='echo [$HOSTNAME] '

DRBD_RESOURCE_NAME=vDrbd
DRBD_CONF_DIR=/etc/drbd.d
DRBD_RESOURCE_FILE=${DRBD_CONF_DIR}/${DRBD_RESOURCE_NAME}.res

# Make sure DRBD resource exists
[ ! -f ${DRBD_RESOURCE_FILE} ] && echo "Error DRBD resource ${DRBD_RESOURCE_NAME} does not exists" && exit 2


echo "##################### DRBD Pacemaker Integration #####################"

pcs cluster cib drbd_cfg
pcs -f drbd_cfg resource create drbd_data ocf:linbit:drbd \
       drbd_resource=${DRBD_RESOURCE_NAME} op monitor interval=60s
pcs -f drbd_cfg resource master drbd_data_clone drbd_data \
       master-max=2 master-node-max=1 clone-max=2 clone-node-max=1 \
       notify=true interleave=true ordered=true target-role=Started

pcs cluster cib-push drbd_cfg

echo "Integrated DRBD master/slave DRBD resources into Pacemaker"
logger "Integrated DRBD master/slave DRBD resources into Pacemaker"
