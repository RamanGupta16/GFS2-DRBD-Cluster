#!/bin/sh
#
# After a cluster node re-starts after going down then 
# re-start the GFS2 resources 
#

# Exit script on error
set -e

DRBD_VolGroup=Cluster_VG_DRBD
DRBD_LogicalVolume=Cluster_LV_DRBD
DRBD_MOUNT_DIR=/backup

# Activate the Logical Volume
lvchange -a y /dev/${DRBD_VolGroup}/${DRBD_LogicalVolume}

# Print GFS2 configuration
tunegfs2 -l /dev/${DRBD_VolGroup}/${DRBD_LogicalVolume}

# Verify /backup is mounted on DRBD block device
if grep -qa ${DRBD_MOUNT_DIR} /proc/mounts; then
  echo "Success: GFS2 formatted /dev/${DRBD_VolGroup}/${DRBD_LogicalVolume} mounted on ${DRBD_MOUNT_DIR}"
else
  echo "Error: Could not mount /dev/${DRBD_BLOCK_DEVICE} on ${DRBD_MOUNT_DIR}"
fi

