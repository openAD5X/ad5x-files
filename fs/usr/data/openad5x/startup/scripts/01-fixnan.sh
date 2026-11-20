#!/bin/sh
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
# Made for the OpenAD5X project
# This file may be distributed under the terms of the MIT license.
#
# Turns on legacy NaN handling in the CPU so the hard-float programs run.
# The register write only applies to the known kernel package.

kver=$(ls /usr/prog/PROGRAM/kernel/ 2>/dev/null | head -n 1)
if [ "$kver" = "2.0.1" ]; then
    busybox devmem 0x00a130d1 8 1
    exit 0
fi
echo "fixnan: kernel package '$kver' not recognised, NaN mode left alone" >&2
exit 1
