#!/bin/sh
#
# Mount the directory over GFS2
#
# The /etc/fstab entry is not updated because Pacemaker will mount the directory
# on Clustered LVM. So the the mount will not happen outside of Pacemaker.
#

# Exit script on error
set -e

alias echo='echo [$HOSTNAME] '

DRBD_MOUNT_DIR=$1
CLUSTER_NAME=$2
DRBD_VolGroup=$3
DRBD_LogicalVolume=$4
DRBD_BLOCK_DEVICE=$5

echo "GFS2 Details"
tunegfs2 -l /dev/${DRBD_VolGroup}/${DRBD_LogicalVolume}
echo ""

# Mount GFS2 filesystem on CLVM Logical Volume
mkdir -p ${DRBD_MOUNT_DIR}
mount -t gfs2 /dev/${DRBD_VolGroup}/${DRBD_LogicalVolume} ${DRBD_MOUNT_DIR}
echo ""
echo "Mounting /dev/${DRBD_VolGroup}/${DRBD_LogicalVolume} with GFS2 Cluster Filesystem at ${DRBD_MOUNT_DIR} ..."

# Verify /backup is mounted on DRBD block device
if grep -qa ${DRBD_MOUNT_DIR} /proc/mounts; then
  echo "Success: /dev/${DRBD_VolGroup}/${DRBD_LogicalVolume} is mounted on ${DRBD_MOUNT_DIR} with GFS2 Filesystem"
else
  echo "Error: Could not mount /dev/${DRBD_BLOCK_DEVICE} on ${DRBD_MOUNT_DIR}"
fi

exit 0

