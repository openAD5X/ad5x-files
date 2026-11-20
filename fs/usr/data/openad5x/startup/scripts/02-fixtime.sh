#!/bin/sh
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
# Made for the OpenAD5X project
# This file may be distributed under the terms of the MIT license.
#
# Sets the clock from time.nist.gov once the network answers
# (up to 30 attempts, 2 s apart).

server=time.nist.gov
attempt=1
while [ "$attempt" -le 30 ]; do
    if ping -c1 -W2 "$server" >/dev/null 2>&1; then
        rdate -s "$server"
        exit 0
    fi
    attempt=$((attempt + 1))
    sleep 2
done
