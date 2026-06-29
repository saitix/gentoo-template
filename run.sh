#!/usr/bin/env bash
set -euo pipefail

pwd=$(pwd)

cd /tmp
git clone https://github.com/oddlama/gentoo-install
cp $pwd/gentoo.conf /tmp/gentoo-install/
cd gentoo-install

#Fixup: issue: https://github.com/oddlama/gentoo-install/issues/153
export DEBUGINFOD_URLS="http://foo.mynet.local/debuginfo https://debuginfod.elfutils.org/" 
export DEBUGINFOD_IMA_CERT_PATH="/etc/certs" 
##

./install.sh

