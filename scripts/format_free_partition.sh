#!/bin/sh
#
# This script creates a logical partition form the available free disk space.
# After partition is created the initial 4GB of space is zeroed out so as to
# destroy any previous filesystem data, journal, tables etc.
#
# This partition is intended to be used as DRBD backing device, though
# can be used for aby other purpose.
#

# Exit script on error
set -e

# Root user
if [ $UID -ne 0 ]; then
  echo "$(basename $0) requires root user login. Permission denied."
  exit 1
fi

# Find free disk partition on first disk. If no free disk partition then exit
DISK=`fdisk -l | grep -m1 Disk | awk '{print $2}' | awk -F ':' '{print $1}'`
if [ -z `parted -m ${DISK} print free | tail -n1 | awk -F ':|;' '{print $5}'` ]; then
  logger "No Free partition found on ${DISK} for DRBD"
  exit 1
fi

# From the free disk partition create DRBD partition.
start_free_space=`parted ${DISK} print free | grep "Free Space" | awk '{var=$1} END {print var}'`
end_free_space=`parted ${DISK} print free | grep "Free Space" | awk '{var=$2} END {print var}'`
parted -a optimal ${DISK} mkpart logical ${start_free_space} ${end_free_space} > /dev/null

# Get the most recent partition created from Free Space
DRBD_DISK_PARTITION_NUMBER=`fdisk -l ${DISK} | awk 'END { print substr($1,length($1)) }'`
DRBD_DISK_PARTITION=${DISK}${DRBD_DISK_PARTITION_NUMBER}
logger "Created DRBD partition(logical) ${DRBD_DISK_PARTITION} from ${start_free_space} to ${end_free_space}"

# Zero out the initial partition area
/usr/bin/dd if=/dev/zero of=${DRBD_DISK_PARTITION} bs=8M count=1000

partprobe

echo ${DRBD_DISK_PARTITION}
