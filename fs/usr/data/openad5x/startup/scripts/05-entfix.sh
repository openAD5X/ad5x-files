#!/bin/sh
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
# Made for the OpenAD5X project
# This file may be distributed under the terms of the MIT license.
#
# Makes Entware available on /opt and runs its init scripts.

entware_dir=/usr/data/bin/opt

# nothing to do when Entware is neither mounted nor installed
if [ ! -x /opt/bin/opkg ] && [ ! -d "$entware_dir" ]; then
    exit 0
fi

# Entware's programs need legacy NaN mode
sh /usr/data/openad5x/startup/scripts/01-fixnan.sh || exit 1

if [ ! -x /opt/bin/opkg ] && ! grep -q ' /opt ' /proc/mounts; then
    mount --bind "$entware_dir" /opt
fi

if [ -x /opt/etc/init.d/rc.unslung ]; then
    /opt/etc/init.d/rc.unslung start
fi
