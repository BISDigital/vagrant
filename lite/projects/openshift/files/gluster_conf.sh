#!/usr/bin/env bash
# Copyright (c) 2016, Department for Business, Energy & Industrial Strategy
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the <organization> nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL BIS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Install and configure a GlusterFS node with nfs-ganesha
#
# http://clusterlabs.org/quickstart-redhat.html
# https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html-single/High_Availability_Add-On_Administration/index.html#s1-clusterconfigure-HAAA
# https://access.redhat.com/documentation/en-US/Red_Hat_Storage/3/html/Administration_Guide/sect-NFS.html
#
# Author: Justin Cook <jhcook@secnix.com>

set -x
#set -o nounset -o errexit

# Configurable options
RUSER="vagrant"
NODE1="ukbeisgls01"
NODE2="ukbeisgls02"

# Add the firewall rules even though we will disable it 
rpm -q firewalld 2>/dev/null
if [ $? -eq 0 ]
then
  firewall-cmd --permanent --add-service=high-availability || /bin/true
  systemctl disable firewalld || /bin/true
  systemctl stop firewalld || /bin/true
fi

# Install dependencies for Gluster repo
rpm --nodeps -ivh http://mirror.centos.org/centos/7/extras/x86_64/Packages/centos-release-storage-common-1-2.el7.centos.noarch.rpm

# Install Gluster repo
yum localinstall -y http://mirror.centos.org/centos/7/extras/x86_64/Packages/centos-release-gluster38-1.0-1.el7.centos.noarch.rpm

# Patch the repo file
sed -i 's/\$releasever/7/g' /etc/yum.repos.d/CentOS-Gluster-3.8.repo

# Install all the necessary packages
yum install -y --enablerepo='centos-gluster38' --enablerepo='rhel-ha-for-rhel-7-server-rpms' \
               --enablerepo='rhel-rs-for-rhel-7-server-rpms' \
               glusterfs-server glusterfs-api glusterfs-ganesha pcs pacemaker ctdb corosync

# Check to see if corosync.conf exists and edit as appropriate
if [ ! -f /etc/corosync/corosync.conf ]
then
  cp /etc/corosync/corosync.conf.example /etc/corosync/corosync.conf
fi

grep "bindnetaddr: 192\.168\.1\.0" /etc/corosync/corosync.conf 2>/dev/null
if [ "$?" -ne 1 ]
then
  sed -i 's/bindnetaddr: 192.168.1.0/bindnetaddr: 0.0.0.0/g' /etc/corosync/corosync.conf
fi

# Remove hostname from loopback address in /etc/hosts
# https://github.com/ClusterLabs/pcs/issues/116
sed -i "/^127\.0\.0\.1\s\+`hostname -s`/d" /etc/hosts

# Enable and start services
systemctl enable glusterd pcsd.service pacemaker.service corosync.service
systemctl start glusterd pcsd.service pacemaker.service corosync.service

# Configure pcsd
echo -ne CHANGEME | passwd --stdin hacluster
if [ "`hostname -s`" = "$NODE1" ]
then
  if [ ! -f /var/lib/glusterd/nfs/secret.pem ]
  then
    ssh-keygen -b 4096 -f /var/lib/glusterd/nfs/secret.pem -q -N ""
    cp /var/lib/glusterd/nfs/secret.pem* /$RUSER/
  fi
  if [ ! -d /root/.ssh ]
  then
    mkdir /root/.ssh
    chown root:root /root/.ssh
    chmod 0700 /root/.ssh
  fi
  if [ ! -f /root/.ssh/secret.pem ]
  then
    cp /var/lib/glusterd/nfs/secret.pem* /root/.ssh/
    chown root:root /root/.ssh/secret.pem
    chmod 0600 /root/.ssh/secret.pem
  fi
#  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
#    /var/lib/glusterd/nfs/secret.pem.pub $RUSER@$NODE2:
#  scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
#    /var/lib/glusterd/nfs/secret.* $RUSER@$NODE2:
  RFILE="`getent passwd $RUSER | awk -F: '{print$6}'`/create_cluster.sh"
  cat > $RFILE <<__EOF__
#!/usr/bin/env bash
pcs cluster auth $NODE1 $NODE2 -u hacluster -p CHANGEME --force
pcs cluster setup --force --name app-gluster $NODE1 $NODE2
pcs cluster start --all
pcs property set stonith-enabled=false
pcs property set no-quorum-policy=ignore
__EOF__
  chmod u+x $RFILE
fi

if [ "`hostname -s`" = "$NODE2" ]
then
  if [ ! -d /root/.ssh ]
  then
    mkdir /root/.ssh
    chown root:root /root/.ssh
    chmod 0700 /root/.ssh
  fi
  if [ ! -f /root/.ssh/secret.pem.pub ]
  then
    cp /$RUSER/secret.pem.pub /root/.ssh/
    cat /root/.ssh/secret.pem.pub >> /root/.ssh/authorized_keys
    chown root:root /root/.ssh/secret.pem.pub
  fi
  if [ ! -d /var/lib/glusterd/nfs ]
  then
    cp /$RUSER/secret.* /var/lib/glusterd/nfs/
  fi
fi
