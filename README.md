# GFS2-DRBD-Cluster
GFS2 Shared-Disk Cluster Filesystem over a Pacemaker 2 nodes cluster using DRBD

## Summary
This collection of scripts aims to create Red Hat GFS2 Clustered Shared-disk Filesystem
over a cluster of 2 nodes. DRBD is used for providing replicated read/write raw disk block access
over the nodes in a Pacemaker/Corosync Cluster. The cluster must have fencing enabled.


## Introduction
A simple motivation of using GFS2 cluster filesystem is to achieve Shared Nothing Live Migration
(LM) of a VM. Live Migration refers to the capability of transferring a running guest
operating system from one physical node to another without interruption. In this process
of LM the underlying assumption is that virtual disks of VMs are shared between source
and target nodes and only running state (memory, configuration) of the VM needs to be migrated.

The shared storage is achieved by hosting virtual disk files of the VM on a NFS mounted
shared server/NAS-Box, thereby giving access to same virtual disks to both the nodes. VM on
any given node uses the same shared virtual disks before or after miugration.

An alternative to NAS shared storage is Storage Area Network (SAN) which provides access to
replicated disk blocks whereby the VM access the shared storage over a storage area network (SAN).
A SAN unlike NAS does not provide filesystem abstraction, only block-level operations. However,
file systems built on top of SANs do provide file-level access and are known as shared-disk
file systems. SAN storage is thus abstracted for the applications using these shared-disk filesystems.
Examles of such shared-disk file systems are GFS2 and OCFS2.
https://en.wikipedia.org/wiki/Clustered_file_system

Another approach for Live Migration is without any shared storage i.e. without using NAS or SAN
in what is called as Shared Noting Live Migration. This approach avoids single point of failure
besides avoiding the need for a third box providing shared storage. In this approach block storage is
replicated without the need for a SAN. To achieve this Distributed Redundant Block Device (DRBD)
is used to provide the back-end storage as a cost-effective alternative to a SAN device.
DRBD keeps shared virtual disks synchronized across cluster nodes by replicating the raw
block devices between them.

DRBD thus can be used instead of SAN. By using GFS2 shared-disk filesystem on top of DRBD, it
provides same filesystem abstraction as SAN. This approach of GFS2 over DRBD is used here to provide
Shared Noting Live Migration of VM between 2 nodes of a Pacemaker Cluster, totally avoiding the need
for any third storage box.


## Pacemaker High Availability Cluster
GFS2-over-DRBD cluster filesystem requires a working cluster to be already deployed over the nodes.
Pacemaker/Corosync provide the HA Cluster framework to create the cluster between 2 nodes.

http://clusterlabs.org/doc/en-US/Pacemaker/1.1/html-single/Clusters_from_Scratch
http://clusterlabs.org/doc/en-US/Pacemaker/1.1/html-single/Pacemaker_Explained


## GFS2
Red Hat Global File System 2 (GFS2) is a shared-disk cluster Filesystem. GFS2 allows all
cluster nodes to have direct concurrent access to the same shared block storage. DRBD
provides shared storage and DLM provides locking to control the access to this shared
storage and maintain its consistency. GFS2 is part Linux Kernel since version 2.6.19.

https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Global_File_System_2/ch-overview-GFS2.html


## Distributed Lock Manager (DLM)
One of the major roles of a cluster is to provide distributed locking for synchronizing access to 
shared clustered resources. Distributed Lock Manager (DLM) provides for the distributed locking
across the cluster, required by GFS2 and CLVM to synchronize their accesses to shared storage.
Whenever GFS2 or CLVM needs a lock, it sends a request to DLM. If the lockspace does not
yet exist, DLM will create it and then give the lock to the requester. Should a subsequant
lock request come for the same lockspace, it will be rejected. Once the application using
the lock is finished, it will release the lock. After this, another node may request and
receive a lock for the lockspace.

If a node fails, the Pacemaker fence daemon will alert DLM that a fence is pending and
new lock requests will block. After a successful fence, fence daemon will alert DLM that
the node is fenced off and any locks the victim node held are released and can be reused.

GFS2 mandates that DLM be running on both nodes, so DLM must be integrated with Pacemaker.

https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/High_Availability_Add-On_Overview/ch-dlm.html


## Clustered Logical Volume Manager (CLVM)
The Clustered Logical Volume Manager (CLVM) is a set of clustering extensions to LVM.
These extensions allow a cluster of computers to manage shared storage using LVM. CLVM
is required because during LM both the cluster nodes are active and require read/write
access to virtual disk blocks.

CLVM uses DLM to prvide safe shared access to raw DRBD block devices. With DRBD providing
the raw storage, CLVM allows creation of clustered Physical Volume(PV), Volume Group(VG)
and Logical Volume(LV) over the nodes. These LVs are where we will create GFS2 and where
VM's virtual disks will reside.

https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Logical_Volume_Manager_Administration/LVM_Cluster_Overview.html


## DRBD
Distributed Replicated Block Device (DRBD) is a software-based, shared-nothing, replicated
storage solution mirroring the content of block devices (hard disks, partitions,
logical volumes etc.) between nodes. DRBD is a technology that takes raw storage from
two nodes and keeps their data synchronized in real-time transparently and synchronously.
It is sometimes described as "Network RAID Level 1". DRBD also provides back-end storage as
a cost-effective alternative to a SAN (Storage Area Network) device.

DRBD supports mainly two modes of operation: Single Primary and Dual Primary. 

### Single-Primary (Primary/Secondary) Mode
In single-primary mode, a resource is, at any given time, in the primary role on only one cluster member.
Since it is guaranteed that only one cluster node manipulates the data at any moment, this mode can be
used with any conventional file system (ext3, ext4, XFS etc). Deploying DRBD in single-primary mode is
the canonical approach for high availability (fail-over capable) clusters.

### Dual-Primary (Primary/Primary) Mode
In dual-primary mode, a resource is, at any given time, in the primary role on both cluster nodes.
Since concurrent access to the data is thus possible, this mode requires the use of a shared cluster
file system that utilizes a distributed lock manager (DLM). Examples include GFS2 and OCFS2.

Deploying DRBD in dual-primary mode is the preferred approach for clusters which require concurrent
data access from two nodes. The prime motivation is Live Migration (LM) of a VM. In LM during the
migration phase it is required that both the nodes involved in migration be able to read/write over
the shared virtual disks.

DRBD defines a virtual block device which has a device major number of 147 assigned by
Linux Assigned Names And Numbers Authority (LANANA http://www.lanana.org/docs/device-list/),
and its minor numbers are numbered from 0 onwards. A DRBD block device is named /dev/drbdX where X
is device minor number e.g. /dev/drbd0. The DRBD block device corresponds to a volume in a resource
configured by DRBD.

In the dual-Primary setup the DRBD virtual block device is setup over the raw disks of the two nodes: 
"node1:/dev/sda6 + node2:/dev/sda6 -> both:/dev/drbd0". In this setup the /dev/drbd0 acts like a raw
disk block over which the Clustered Logical Volume Manager (CLVM) is used to manage the shared storage.

http://docs.linbit.com/doc/users-guide-84/drbd-users-guide/


## Technology Stack
The technology stack (except VM) constructed upon successfull execution of master script
'install_drbd_dual_primary.sh' is shown below. Pacemaker/Corosync (PCS)
provides Cluster framework which integrates DLM/CLVM/DRBD resources.

<pre>
          |----------------|                                  |----------------|
          |    VM          |   <------------------------>     |    VM          |
          |----------------|          Live Migration          |----------------|
          | KVM/QEMU       |   <------------------------>     | KVM/QEMU       |
    C  /\ |----------------|                                  |----------------|
    L  |  |  GFS2/DLM      |   <=== Cluster Aware FS ===>     |  GFS2/DLM      |
P   U  |  |----------------|                                  |----------------|
C   S  |  |  LV/VG/PV      |   <======== CLVM  =========>     |  LV/VG/PV      |
S   T  |  |----------------|                                  |----------------|
    E  |  |  DRBD          |   <====== /dev/drbd0 ======>     |  DRBD          |
    R  \/ |----------------|                                  |----------------|
          | Disk Partition |                                  | Disk Partition |
          |----------------|                                  |----------------|
</pre>

## Test Environment:
1. Tested on CentOS 7.3 (both nodes)
2. DRBD version 8.4
3. gfs2-utils-3.1.9-3.el7.x86_64
4. Pacemaker 1.1.15-11.el7_3.4
5. corosync-2.4.0-4.el7.x86_64


## Requirements & Assumptions
1. yum install lvm2-cluster gfs2-utils.
2. The 'install_gfs2_using_drbd.sh' is the master script to create GFS2 over DRBD.
   The script requires free disk space over which it will create DRBD partition.
3. The script assumes a 2 node fencing enabled Pacemaker Cluster to be already present on
   both the nodes. The script bundle does not execute any Pacemaker (pcs) commands but
   assumes Pacemaker Cluster is currently running between the two nodes.
4. DLM and CLVM resources are already managed by Pacemaker Cluster.
5. Passwordless SSH access between the 2 nodes.


## Steps:
1.  Start 2 node (serevr4/server7) Pacemaker cluster.
2.  Configure DLM and CLVM into Pacemaker.
3.  Start master script 'install_gfs2_using_drbd.sh' to initialize GFS2 and DRBD.
4.  Verify DRBD is in dual-Primary mode then configure Pacemaker for DRBD.
    Verify CLVM is configured properly by executing LVM commands: lvdispaly, pvdisplay and vgdisplay on both nodes.
    Verify GFS2 is configured properly by checking mounted filesystem, execute commands: df -hT on both nodes.
5.  Create KVM VM on serevr4 with virtual disks on GFS2 mount directory. Keep
    pinging VM from a third node.
6.  Perform Live Migration of VM from serevr4 to serevr7 once DRBD initial sync is
    complete.
7.  Since disks are already sync'd by DRBD so VM should be migrated quickly.
    Verify ping is continously working.
8.  Shutdown server4 and make sure VM on other node (server7) is workinf fine.
9.  Start server4, start its Pacemaker Cluster and verify
    DRBD is back in dual-Primary mode.
10. Reverse migrate VM from server7 to server4. Ping must not break.


## Result:
In a Pacemaker Cluster with GFS2-over-DRBD setup a VM (4GB-RAM, 4-vCPU) was successfully
Live Migrated in Shared Nothing fashion. It took < 20 seconds to migrate using back-to-back
ethernet connection between the 2 cluster nodes. DRBD was running over same back-to-back
ethernet connection. After migration the non-VM hosting node was shutdown. In surviving node
all the cluster resources and VM were working fine. When the down node was UP again and
joined back into the cluster, all cluster resources and VM was working fine.

