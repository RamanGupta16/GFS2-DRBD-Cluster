#!/bin/sh
#
# Mount the directory over GFS2
#
# Update /etc/fstab entry with GFS2 mount information.
#
#

# Exit script on error
set -e

alias echo='echo [$(uname -n)]  '

DRBD_MOUNT_DIR=$1
CLUSTER_NAME=$2
DRBD_VolGroup=$3
DRBD_LogicalVolume=$4
DRBD_BLOCK_DEVICE=$5

echo "GFS2 details"
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

# Add entry in /etc/fstab on both nodes
tunegfs2 -l /dev/${DRBD_VolGroup}/${DRBD_LogicalVolume} | grep UUID | awk '{print $4}' | sed -e 's/\(.*\)/UUID=\L\1\E\t\'${DRBD_MOUNT_DIR}'\tgfs2\tdefaults,noatime,nodiratime\t0 0/' >> /etc/fstab

echo "Updated /etc/fstab with GFS2 filesystem mount information"

exit 0


