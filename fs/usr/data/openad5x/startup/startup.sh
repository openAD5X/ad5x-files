#!/bin/sh
# OpenAD5X startup: firmwareExe runs this once per boot. It starts each script
# in startup/scripts/ in name order, every one in the background, with its
# output in /tmp/<script>.log.
#
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
#
# Made for the OpenAD5X project
#
# This file may be distributed under the terms of the MIT license.

SCRIPTS=/usr/data/openad5x/startup/scripts
LOG=/tmp/openad5x.log

for script in "$SCRIPTS"/*.sh; do
    [ -f "$script" ] || continue
    name=${script##*/}
    echo "startup: $name" >> "$LOG"
    sh "$script" > "/tmp/$name.log" 2>&1 &
done
