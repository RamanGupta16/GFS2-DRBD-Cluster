#!/bin/sh
#
# This script modifies /etc/lvm/lvm.conf so that it can be used
# for Clustered LVM (cLVM) systems using DRBD dual-Primary mode for
# Cluster Filesystem like GFS2. It does two things:
# 
# 1. Enable clustered locking for LVM.
#
# 2. Add filter in lvm.conf to let LVM filter only DRBD devices on both the cluster nodes
#

# Exit script on error
set -e

# Root user
if [ $UID -ne 0 ]; then
  echo "$(basename $0) requires root user login. Permission denied."
  exit 1
fi

# Save the original LVM conf file
cp /etc/lvm/lvm.conf /etc/lvm/lvm.conf.backup
 
# Enable clustered locking for LVM
lvmconf --enable-cluster

# Disallow fall-back to local locking
sed -i -e 's/fallback_to_local_locking = 1/fallback_to_local_locking = 0/' /etc/lvm/lvm.conf

# Add filter in lvm.conf to let LVM filter(use) only DRBD devices on both the nodes
# filter = [ "a|/dev/drbd*|", "r/.*/" ]
LINE=$(grep -n -P '# filter = \[ "a\|\.\*\/\|"' /etc/lvm/lvm.conf | awk ' END {print $1}' | cut -d':' -f1)
let LINE=$LINE+1
sed -i -e $LINE'i\ \tfilter = [ "a|/dev/drbd*|", "r|.*|" ]' /etc/lvm/lvm.conf

logger "Added DRBD device filter in lvm.conf"
exit 0

