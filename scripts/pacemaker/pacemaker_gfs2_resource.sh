#!/bin/sh
#
# Integrate GFS2-over-CLVM as cloned Pacemaker resource.
#
# Pacemaker ordering resource constraints:
# Start & Promote DRBD then start DLM then start CLVM then start GFS2
#

#set -x
set -e

alias echo='echo [$HOSTNAME] '

DRBD_VolGroup=Cluster_VG_DRBD
DRBD_LogicalVolume=Cluster_LV_DRBD
DRBD_MOUNT_DIR=/backup

echo "##################### GFS2 Pacemaker Integration #####################"

pcs cluster cib fs_cfg
pcs -f fs_cfg resource create Gfs2FS ocf:heartbeat:Filesystem \
       device="/dev/${DRBD_VolGroup}/${DRBD_LogicalVolume}"  \
       directory="${DRBD_MOUNT_DIR}" \
       fstype="gfs2" options="noatime,nodiratime" \
       op monitor interval=10s on-fail=fence
pcs -f fs_cfg resource clone Gfs2FS clone-max=2 clone-node-max=1 interleave=true ordered=true

pcs cluster cib-push fs_cfg

echo "Integrated GFS2 cloned resources into Pacemaker"
logger "Integrated GFS2 cloned resources into Pacemaker"
