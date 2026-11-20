#!/bin/sh
# Starts the OpenAD5X updater (../openad5x_updater.py), which applies what
# Moonraker's update manager pulls into /usr/data/openad5x/ad5x-fs.
# Log: /tmp/openad5x-updater.log
#
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
#
# Made for the OpenAD5X project
#
# This file may be distributed under the terms of the MIT license.

PYTHON=/usr/data/python-hf/bin/python3
UPDATER=/usr/data/openad5x/startup/openad5x_updater.py

if [ ! -x "$PYTHON" ] || [ ! -f "$UPDATER" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') updater not started: $PYTHON or $UPDATER is missing" >> /tmp/openad5x-updater.log
    exit 0
fi
exec "$PYTHON" "$UPDATER"
