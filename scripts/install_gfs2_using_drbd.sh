#!/bin/sh
#
# Configure the Clustered Shared-disk Filesystem GFS2 using DRBD for providing
# raw disk block access over 2 nodes in a Cluster. GFS2 requires a working
# Cluster to be already deployed on the nodes. Pacemaker/Corosync
# provide the HA Cluster framework.
#
# Configure DRBD in dual Primary (Primary-Primary) configuration. DRBD provides
# back-end storage as a cost-effective alternative to a SAN (Storage Area Network) device.
#
# The script bundle assumes a 2 node fencing enabled Cluster to be already present on
# both the nodes with DLM and cLVM resources configured.
# It also assumes free disk space over which the script will create DRBD partition.
#
# The technology stack (except VM) constructed upon successfull execution of this
# script is shown below.
#
# A typical use case of such an architecture is for Live Migration of VMs betwwen the 2
# cluster nodes without the need of shared storage. Thus this avoids the need
# for common NAS mounted storage between the 2 nodes or the need for costly SAN devices.
# In effect this provides for Shared-Nothing Live Migration of VM.
#
#
#        |----------------|                                  |----------------|
#        |    VM          |   <------------------------>     |    VM          |
#        |----------------|          Live Migration          |----------------|
#        | KVM/QEMU       |   <------------------------>     | KVM/QEMU       |
#  C  /\ |----------------|                                  |----------------|
#  L  |  |  GFS2/DLM      |   <=== Cluster Aware FS ===>     |  GFS2/DLM      |
#  U  |  |----------------|                                  |----------------|
#  S  |  |  LV/VG/PV      |   <======== cLVM  =========>     |  LV/VG/PV      |
#  T  |  |----------------|                                  |----------------|
#  E  |  |  DRBD          |   <====== /dev/drbd0 ======>     |  DRBD          |
#  R  \/ |----------------|                                  |----------------|
#        | Disk Partition |                                  | Disk Partition |
#        |----------------|                                  |----------------|
#
#
# Script Bundle Structure:
# ----------------------------
# This script (install_gfs2_using_drbd.sh) is the master script which uses other
# scripts to complete its job. Use only this script to create GFS2-over-DRBD
# stack. See the requirements and assumptions in the README.md file before
# proceeding with this script bundle.
#
# Notes:
# ---------
# ) RHEL suggests to Avoid SELinux on GFS2:
#   https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Global_File_System_2/s2-selinux-gfs2-gfs2.html
# ) DRBD, GFS2, DLM and cLVM must be managed by Cluster Framework Pacemaker. This script does not do Pacemaker integration.
#
#

SCRIPT_NAME=$(basename $0)

#set -x
set -e

# Root user
if [ $UID -ne 0 ]; then
  echo "DRBD configuration requires root user login. Permission denied."
  exit 1
fi

usage()
{
  echo "Usage  : ${SCRIPT_NAME} FirstPrimaryIPAddress SecondPrimaryIPAddress ClusterName"
  echo "Example: ${SCRIPT_NAME} 192.168.11.100 192.168.11.200 vCluster"
  echo ""
}

# Verify valid argument count
if [ "$#" -ne 3 ]; then
  usage
  exit 1
fi

# Make sure provided cluster is started
[ "`pcs status | grep name | cut -f2 -d':' | tr -d [:space:]`" != "$3" ] && \
echo "Error: Cluster is not started. Please start Cluster $3 before executing this script." && \
exit 1

FIRST_PRIMARY_HOST_NAME=
FIRST_PRIMARY_IP_ADDRESS=$1
SECOND_PRIMARY_HOST_NAME=
SECOND_PRIMARY_IP_ADDRESS=$2
CLUSTER_NAME=$3

LOCAL_IP_ADDRESS=
PEER_IP_ADDRESS=

LOCAL_DRBD_DISK_PARTITION=
PEER_DRBD_DISK_PARTITION=

DRBD_BLOCK_DEVICE=drbd0
DRBD_VolGroup=Cluster_VG_DRBD
DRBD_LogicalVolume=Cluster_LV_DRBD

DRBD_RESOURCE_NAME=vDrbd
DRBD_CONF_DIR=/etc/drbd.d
DRBD_RESOURCE_FILE=${DRBD_CONF_DIR}/${DRBD_RESOURCE_NAME}.res
DRBD_GLOBAL_COMMON_CONF_FILE=${DRBD_CONF_DIR}/global_common.conf

DRBD_MOUNT_DIR=/backup

alias echo='echo [$(uname -n)]  '

validate_ip()
{
  ipcalc -c ${FIRST_PRIMARY_IP_ADDRESS}
  ipcalc -c ${SECOND_PRIMARY_IP_ADDRESS}

  ping -c 2 ${FIRST_PRIMARY_IP_ADDRESS} > /dev/null
  ping -c 2 ${SECOND_PRIMARY_IP_ADDRESS} > /dev/null

  # Set current host
  IP_1=$(ip -o addr | grep ${FIRST_PRIMARY_IP_ADDRESS} | awk '{print $4}' | cut -f1 -d '/')
  IP_2=$(ip -o addr | grep ${SECOND_PRIMARY_IP_ADDRESS} | awk '{print $4}' | cut -f1 -d '/')
  if [ x${IP_1} = x${FIRST_PRIMARY_IP_ADDRESS} ]; then
   LOCAL_IP_ADDRESS=${FIRST_PRIMARY_IP_ADDRESS}
   FIRST_PRIMARY_HOST_NAME=$(uname -n)
   PEER_IP_ADDRESS=${SECOND_PRIMARY_IP_ADDRESS}
   SECOND_PRIMARY_HOST_NAME=`ssh $(whoami)@${PEER_IP_ADDRESS} uname -n`
  elif [ x${IP_2} = x${SECOND_PRIMARY_IP_ADDRESS} ]; then
   LOCAL_IP_ADDRESS=${SECOND_PRIMARY_IP_ADDRESS}
   SECOND_PRIMARY_HOST_NAME=$(uname -n)
   PEER_IP_ADDRESS=${FIRST_PRIMARY_IP_ADDRESS}
   FIRST_PRIMARY_HOST_NAME=`ssh $(whoami)@${PEER_IP_ADDRESS} uname -n`
  else
    echo "Error: One of Provided IP Addresses must exist on host system!"
    exit 1
  fi

  echo ""
  echo "LocalNode ${LOCAL_IP_ADDRESS}   PeerNode ${PEER_IP_ADDRESS}" 
}

format_disk()
{
  # Format Local Disk
  echo "Creating local DRBD partition ..."
  LOCAL_DRBD_DISK_PARTITION=`format_free_partition.sh | tr -d [:space:]`
  echo "Created local DRBD partition ${LOCAL_DRBD_DISK_PARTITION} ..."

  echo ""

  # Format Peer Disk
  echo "Creating peer DRBD partition ..."
  PEER_DRBD_DISK_PARTITION=`ssh $(whoami)@${PEER_IP_ADDRESS} format_free_partition.sh | tr -d [:space:]`
  echo "Created peer DRBD partition ${PEER_DRBD_DISK_PARTITION} ..."
}

configure_drbd()
{
  #if [ -f ${DRBD_RESOURCE_FILE} ]; then
  #  echo "DRBD already configured with resource file ${DRBD_RESOURCE_FILE} exiting..."
  #  exit 1
  #fi

  echo ""
  echo "Creating Primary-Primary (dual Primary) DRBD resource file ${DRBD_RESOURCE_FILE}"

  # Create backup of existing DRBD global common conf file 
  mv ${DRBD_GLOBAL_COMMON_CONF_FILE} ${DRBD_GLOBAL_COMMON_CONF_FILE}.backup
  ssh $(whoami)@${PEER_IP_ADDRESS} mv ${DRBD_GLOBAL_COMMON_CONF_FILE} ${DRBD_GLOBAL_COMMON_CONF_FILE}.backup

  # Create DRBD config
  create_drbd_config.sh ${DRBD_RESOURCE_NAME} ${DRBD_BLOCK_DEVICE} \
                        ${LOCAL_IP_ADDRESS} ${LOCAL_DRBD_DISK_PARTITION} \
                        ${PEER_IP_ADDRESS} ${PEER_DRBD_DISK_PARTITION}

  # Copy the DRBD resource configuration file and global common file to peer DRBD Node
  scp ${DRBD_RESOURCE_FILE} $(whoami)@${PEER_IP_ADDRESS}:${DRBD_RESOURCE_FILE}
  scp ${DRBD_GLOBAL_COMMON_CONF_FILE} $(whoami)@${PEER_IP_ADDRESS}:${DRBD_GLOBAL_COMMON_CONF_FILE}

  # Ensure the DRBD kernel module is loaded on both nodes
  modprobe drbd
  ssh $(whoami)@${PEER_IP_ADDRESS} modprobe drbd

  # Initializes the meta data storage on both nodes
  drbdadm create-md ${DRBD_RESOURCE_NAME}
  ssh $(whoami)@${PEER_IP_ADDRESS} drbdadm create-md ${DRBD_RESOURCE_NAME}

  # Attach backing disk to DRBD device and connect to peer
  drbdadm up ${DRBD_RESOURCE_NAME}
  ssh $(whoami)@${PEER_IP_ADDRESS} drbdadm up ${DRBD_RESOURCE_NAME}

  # Start DRBD services
  systemctl start drbd.service
  ssh $(whoami)@${PEER_IP_ADDRESS} systemctl start drbd.service
  
  # Promote DRBD resource to Primary. Local Primary DRBD node is the initial sync source
  drbdadm primary --force ${DRBD_RESOURCE_NAME}
  ssh $(whoami)@${PEER_IP_ADDRESS} drbdadm primary ${DRBD_RESOURCE_NAME}

  echo "Success: Started DRBD on ${LOCAL_IP_ADDRESS} node. Use drbd-overview and /proc/drbd to monitor DRBD."
  echo "DRBD Node ${LOCAL_IP_ADDRESS} role: `drbdadm role ${DRBD_RESOURCE_NAME} | cut -f1 -d'/'`"
  echo "DRBD Node ${LOCAL_IP_ADDRESS} connection state: `drbdadm cstate ${DRBD_RESOURCE_NAME}`"
  echo ""
  echo "Success: Started DRBD on ${PEER_IP_ADDRESS} node. Use drbd-overview and /proc/drbd to monitor DRBD. "
  echo "DRBD Node ${PEER_IP_ADDRESS} role: `ssh $(whoami)@${PEER_IP_ADDRESS} drbdadm role ${DRBD_RESOURCE_NAME} | cut -f1 -d'/'`"
  echo "DRBD Node ${PEER_IP_ADDRESS} connection state: `ssh $(whoami)@${PEER_IP_ADDRESS} drbdadm cstate ${DRBD_RESOURCE_NAME}`"

  echo ""
  echo "Started DRBD initial sync..."
  echo ""
}

lvm_structure()
{
  # Edit /etc/lvm/lvm.conf on both nodes
  clvm_config.sh
  ssh $(whoami)@${PEER_IP_ADDRESS} clvm_config.sh 

  ##### Create LVM structure over DRBD partition: Physical Vol, Vol Group, Logical Vol ####

  echo "Creating Clustered Physical Volume over DRBD device ${DRBD_BLOCK_DEVICE}"
  pvcreate /dev/${DRBD_BLOCK_DEVICE}

  echo "Creating Clustered Volume Group ${DRBD_VolGroup} over /dev/${DRBD_BLOCK_DEVICE}"
  vgcreate --clustered y ${DRBD_VolGroup} /dev/${DRBD_BLOCK_DEVICE}

  # LV size in nearest floor integer
  DRBD_LV_SIZE=`pvs /dev/${DRBD_BLOCK_DEVICE} -o pv_size --noheadings | awk '{units=substr($1, length($1)); printf(int($1))units}'`
  echo "Creating Clustered Logical Volume ${DRBD_LogicalVolume} over ${DRBD_VolGroup} of size ${DRBD_LV_SIZE}"
  lvcreate --size ${DRBD_LV_SIZE} --name ${DRBD_LogicalVolume} ${DRBD_VolGroup}

  echo "Local Node Cluster LV :"
  lvscan
  echo ""

  echo "Peer Node Cluster LV :"
  ssh $(whoami)@${PEER_IP_ADDRESS} lvscan
  echo ""
}

configure_filesystem()
{
  # Format the clustered LV to use GFS2 Clustered filesystem
  mkfs.gfs2 -p lock_dlm -t ${CLUSTER_NAME}:vGFS2 -j 2 /dev/${DRBD_VolGroup}/${DRBD_LogicalVolume}
  echo "Creating GFS2 Cluster Filesystem over /dev/${DRBD_VolGroup}/${DRBD_LogicalVolume} ..."

  # Format the clustered LV to use GFS2 Clustered filesystem
  configure_filesystem.sh ${DRBD_MOUNT_DIR} ${CLUSTER_NAME} ${DRBD_VolGroup} ${DRBD_LogicalVolume} ${DRBD_BLOCK_DEVICE}
  ssh $(whoami)@${PEER_IP_ADDRESS} configure_filesystem.sh ${DRBD_MOUNT_DIR} ${CLUSTER_NAME} ${DRBD_VolGroup} ${DRBD_LogicalVolume}

  df -hT | grep gfs2
  ssh $(whoami)@${PEER_IP_ADDRESS} df -hT | grep gfs2
}

#Validate IP Address
validate_ip

# Find and format free disk partition
format_disk

# Configure DRBD device as dual-primary
configure_drbd

# Create cLVM structure over DRBD device
lvm_structure

# Create Filesystem
configure_filesystem
