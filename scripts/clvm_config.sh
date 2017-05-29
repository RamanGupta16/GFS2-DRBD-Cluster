#!/bin/sh
#
# This script modifies /etc/lvm/lvm.conf so that it can be used
# for Clustered LVM (cLVM) systems using DRBD dual-Primary mode for
# Cluster Filesystem like GFS2.
#
# Add filter in lvm.conf to scan DRBD block devices and standard disk
# partition except the DRBD backing partition.
#
# Note:
# Enable clustered locking for LVM is done when CLVM is integrated
# with Pacemaker with command: lvmconf --enable-cluster
#

# Exit script on error
set -e

DRBD_DISK_PARTITION=$1
DISK=`echo ${DRBD_DISK_PARTITION%?}`

# Root user
if [ $UID -ne 0 ]; then
  echo "$(basename $0) requires root user login. Permission denied."
  exit 1
fi

# Add filter in lvm.conf
LINE=$(grep -n -P '# filter = \[ "a\|\.\*\/\|"' /etc/lvm/lvm.conf | awk ' END {print $1}' | cut -d':' -f1)
let LINE=$LINE+1
sed -i -e $LINE'i\ \tfilter = [ "a|/dev/drbd*|", "r|'${DRBD_DISK_PARTITION}'|", "a|'${DISK}'*|"  ]' /etc/lvm/lvm.conf

logger "Added DRBD device filter in lvm.conf"
exit 0

