#!/bin/sh
#
# Create DRBD dual-Primary resource configuration file from the supplied parameters.
# Modify the Global Common Conf file and backup default file.
#

DRBD_RESOURCE_NAME=$1
DRBD_BLOCK_DEVICE=$2
FIRST_PRIMARY_IP_ADDRESS=$3
FIRST_PRIMARY_DRBD_DISK_PARTITION=$4
SECOND_PRIMARY_IP_ADDRESS=$5
SECOND_PRIMARY_DRBD_DISK_PARTITION=$6

FIRST_PRIMARY_HOST_NAME=`ssh $(whoami)@${FIRST_PRIMARY_IP_ADDRESS} uname -n`
SECOND_PRIMARY_HOST_NAME=`ssh $(whoami)@${SECOND_PRIMARY_IP_ADDRESS} uname -n`

DRBD_CONF_DIR=/etc/drbd.d
DRBD_RESOURCE_FILE=${DRBD_CONF_DIR}/${DRBD_RESOURCE_NAME}.res
DRBD_GLOBAL_COMMON_CONF_FILE=${DRBD_CONF_DIR}/global_common.conf
DRBD_SYNC_PORT=7789

# Create DRBD global conf file
cat > ${DRBD_GLOBAL_COMMON_CONF_FILE} <<EOF
global
{
	usage-count no;
}

common
{
  handlers
  {
    fence-peer    "/usr/lib/drbd/crm-fence-peer.sh";
    after-resync-target "/usr/lib/drbd/crm-unfence-peer.sh";
  }

  startup
  {
    wfc-timeout           300;
    degr-wfc-timeout      120;
    outdated-wfc-timeout  120;
    become-primary-on     both;
  }

  disk
  {
    fencing   resource-and-stonith;
	}
}
EOF


# Create DRBD Resource File
cat > ${DRBD_RESOURCE_FILE} <<EOF
resource ${DRBD_RESOURCE_NAME}
{
  protocol    C;
  meta-disk   internal;

  on ${FIRST_PRIMARY_HOST_NAME}
  {
    device    /dev/${DRBD_BLOCK_DEVICE};
    disk      ${FIRST_PRIMARY_DRBD_DISK_PARTITION};
    address   ${FIRST_PRIMARY_IP_ADDRESS}:${DRBD_SYNC_PORT};
  }

  on ${SECOND_PRIMARY_HOST_NAME}
  {
    device    /dev/${DRBD_BLOCK_DEVICE};
    disk      ${SECOND_PRIMARY_DRBD_DISK_PARTITION};
    address   ${SECOND_PRIMARY_IP_ADDRESS}:${DRBD_SYNC_PORT};
  }

  net
  {
    verify-alg            sha1;
    csums-alg             sha1;
    allow-two-primaries   yes;
    after-sb-0pri         discard-zero-changes;
    after-sb-1pri         discard-secondary;
    after-sb-2pri         disconnect;
  }

  disk
  {
    resync-rate   100M;
  }
}
EOF
