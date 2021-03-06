#!/usr/bin/env bash
# Copyright (c) 2016, Department for Business, Innovation and Skills
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

# Look for a private key "id_rsa" and copy it over for use within the guest.

set -o nounset
set -o errexit
set -o pipefail

if [ ! -f "/etc/yum.repos.d/epel.repo" ]
then
  rpm -i https://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-6.noarch.rpm
fi

subscription-manager clean
subscription-manager register --auto-attach --username=$SUB_USERNAME --password=$SUB_PASSWORD
subscription-manager repos --enable=rhel-7-server-extras-rpms
subscription-manager repos --enable=rhel-7-server-extras-rpms
subscription-manager repos --enable=rhel-7-server-optional-rpms

yum -y install ansible
yum -y install git

if [ -f /vagrant/id_rsa ] 
then
  if [ ! -d ~vagrant/.ssh ]
  then
    mkdir ~vagrant/.ssh
    chmod 700 ~vagrant/.ssh
  fi
  cp /vagrant/id_rsa ~vagrant/.ssh/
  chmod 600 ~vagrant/.ssh/id_rsa
fi

# Checkout the BISDigital/infrastructure Github repo to /opt/ and link the 
# directory to /etc.

mkdir -p /opt/BISDigital/infrastructure && chown vagrant:vagrant \
  /opt/BISDigital/infrastructure
su -l vagrant << __EOF__
cd /opt/BISDigital/infrastructure
git init
git remote add -f origin https://github.com/BISDigital/infrastructure.git
git config core.sparsecheckout true
echo "ansible/" >> .git/info/sparse-checkout
git pull origin master
__EOF__

mv /etc/ansible /root/ansible.orig
ln -s /opt/BISDigital/infrastructure/ansible /etc/ansible
