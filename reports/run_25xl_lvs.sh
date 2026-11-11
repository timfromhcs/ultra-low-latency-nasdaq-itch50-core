#!/usr/bin/env bash
set -u
BIN=/nix/store/1pkfh3p98m8i3jp642n3bznpjfq65i6m-python3-3.13.9-env/bin/librelane
cd /home/tim/chiplab-native
$BIN --pdk-root /opt/ciel --last-run openlane/sky130_wrap32_25ns_xl.json \
  --from Netgen.LVS \
  > /home/tim/chiplab-native/ns25xl-lvs.log 2>&1
echo "EXIT=$?" >> /home/tim/chiplab-native/ns25xl-lvs.log
