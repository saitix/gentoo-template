#!/usr/bin/env bash
set -euo pipefail

pwd=$(pwd)

cd /tmp
git clone https://github.com/oddlama/gentoo-install
cp $pwd/gentoo.conf /tmp/gentoo-install/
cd gentoo-install
./install.sh

