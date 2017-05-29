#!/bin/sh
#
# High level user visible script:
#
# Install GFS2 using DLM & CLVM over dual-Primary DRBD in a 2 node Pacemaker Cluster.
# Integrate GFS2, CLVM, DLM and DRBD as Pacemaker resources
#
#

set -e

# Gather Cluster Information
LOCAL_NODE_CLUSTER_IP_ADDRESS=$(gethostip -d `pcs status corosync | grep local |  awk '{print $3}'`)
PEER_NODE_CLUSTER_IP_ADDRESS=$(gethostip -d `pcs status corosync | grep -v local | tail -1 | awk '{print $3}'`)
CLUSTER_NAME=$(grep CLUSTER_NAME /etc/vPacemaker.conf | cut -f2 -d=)

echo "Wait for cluster to stabilize..."
sleep 5

# Integrate DLM and CLVM with Pacemaker
pacemaker_dlm_clvm_resource.sh

# Master script to configure DRBD, CLVM and GFS2
configure_gfs2_using_drbd.sh ${LOCAL_NODE_CLUSTER_IP_ADDRESS} ${PEER_NODE_CLUSTER_IP_ADDRESS} ${CLUSTER_NAME}

# Integrate DRBD with Pacemaker
pacemaker_drbd_resource.sh

# Integrate GFS2 with Pacemaker
pacemaker_gfs2_resource.sh

# Setup constraints
pacemaker_constraints.sh

