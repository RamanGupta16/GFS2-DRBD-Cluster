#!/bin/sh
#
# UNDO the GFS2-DRBD configuration on both nodes:
#
# 1) unmount the GFS2 mount point.
# 2) LVM: Remove Logical Vol, Vol Group and Physical Vol.
# 3) Stop DRBD. Obsolete the resource file and restore global common conf file.
# 4) Restore original LVM configuration file.
# 5) Free the DRBD partition.
#

SCRIPT_NAME=$(basename $0)

# Print the cmds executed
#set -x

# Exit script on error
#set -e

# Root user
if [ $UID -ne 0 ]; then
  echo "DRBD configuration requires root user login. Permission denied."
  exit 1
fi

DRBD_RESOURCE_NAME=vDrbd
DRBD_CONF_DIR=/etc/drbd.d
DRBD_RESOURCE_FILE=${DRBD_CONF_DIR}/${DRBD_RESOURCE_NAME}.res
DRBD_GLOBAL_COMMON_CONF_FILE=${DRBD_CONF_DIR}/global_common.conf
DRBD_MOUNT_DIR=/backup

DRBD_BLOCK_DEVICE=drbd0
DRBD_VolGroup=Cluster_VG_DRBD
DRBD_LogicalVolume=Cluster_LV_DRBD

LOCAL_IP_ADDRESS=
LOCAL_DISK=
LOCAL_PARTITION=

PEER_IP_ADDRESS=
PEER_DISK=
PEER_PARTITION=

# Read IP Address, DRBD partition from DRBD_RESOURCE_FILE
disk=
partition=
data_list=$(egrep ' disk.*;|address' ${DRBD_RESOURCE_FILE} | awk '{ print $2}' | cut -d':' -f1)
for item in ${data_list}; do
 if [[ $item = *dev* ]]; then # Read information from 'disk    /dev/sda6'
   disk=`echo $item | cut -d';' -f1`
   partition=`echo $disk | grep -o '.$'`
   disk=`echo ${disk%?}`
 elif ip -o addr | grep $item > /dev/null; then # match local IP Address
   LOCAL_IP_ADDRESS=$item
   LOCAL_DISK=$disk
   LOCAL_PARTITION=$partition
 else
   PEER_IP_ADDRESS=$item
   PEER_DISK=$disk
   PEER_PARTITION=$partition
 fi
done


#Before uinstalling DRBD stop any apps using DRBD partition, close files on /backup etc.
if lsof | grep ${DRBD_MOUNT_DIR} > /dev/null; then
  echo "Before uinstalling DRBD stop any application(VM) on DRBD partition mounted ${DRBD_MOUNT_DIR}"
  exit 1
fi

# Unmount the GFS2 mounted dir
umount ${DRBD_MOUNT_DIR}
ssh $(whoami)@${PEER_IP_ADDRESS} umount ${DRBD_MOUNT_DIR}

# Undo cLVM structure
lvremove  /dev/${DRBD_VolGroup}/${DRBD_LogicalVolume}
vgremove ${DRBD_VolGroup}
pvremove /dev/${DRBD_BLOCK_DEVICE}

# Stop DRBD
drbdadm down ${DRBD_RESOURCE_NAME}
ssh $(whoami)@${PEER_IP_ADDRESS} drbdadm down ${DRBD_RESOURCE_NAME}

systemctl stop drbd.service
ssh $(whoami)@${PEER_IP_ADDRESS} systemctl stop drbd.service

# Make current DRBD resource file old
mv ${DRBD_RESOURCE_FILE} ${DRBD_RESOURCE_FILE}.old
ssh $(whoami)@${PEER_IP_ADDRESS} mv ${DRBD_RESOURCE_FILE} ${DRBD_RESOURCE_FILE}.old

# Restore original DRBD global common conf
mv ${DRBD_GLOBAL_COMMON_CONF_FILE}.backup ${DRBD_GLOBAL_COMMON_CONF_FILE}
ssh $(whoami)@${PEER_IP_ADDRESS} mv ${DRBD_GLOBAL_COMMON_CONF_FILE}.backup ${DRBD_GLOBAL_COMMON_CONF_FILE}

# Restore orifinal default lvm.conf
lvmconfig --type default --withcomments --withspaces --ignorelocal  > /etc/lvm/lvm.conf
scp /etc/lvm/lvm.conf $(whoami)@${PEER_IP_ADDRESS}:/etc/lvm/lvm.conf

# Delete the created partition and make it free again
if [ -n "${LOCAL_DISK}" -a -n "${LOCAL_PARTITION}" ]; then
  parted ${LOCAL_DISK} rm ${LOCAL_PARTITION}
fi

if [ -n "${PEER_PARTITION}" -a -n "${PEER_DISK}" ]; then
  ssh $(whoami)@${PEER_IP_ADDRESS} parted ${PEER_DISK} rm ${PEER_PARTITION}
fi

echo "GFS2-DRBD uninstall"
logger "GFS2-DRBD uninstalled"

