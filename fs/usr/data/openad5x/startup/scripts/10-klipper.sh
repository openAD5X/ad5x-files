#!/bin/sh
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
# Made for the OpenAD5X project
# This file may be distributed under the terms of the MIT license.
#
# Runs Kalico (Klippy) and starts it again whenever it stops.

msg_file=/tmp/openad5x.log
kroot=/usr/data/openad5x/klipper
kpython=$kroot/klippy-env/bin/python
afc_dir=$kroot/config/AFC
export PATH=$PATH:/opt/bin

note() {
    echo "$1" >> "$msg_file"
}

# AFC refuses to load with a missing or empty state file; an empty JSON
# object is enough, AFC writes the real contents later.
for state in "$afc_dir/AFC.var.unit" "$afc_dir/AFC.var"; do
    [ -s "$state" ] && continue
    mkdir -p "$afc_dir"
    echo '{}' > "$state"
done

# the eboard must be running its application first (08-mcu-wake.sh);
# give it up to 90 s
waited=0
until [ -e /tmp/openad5x-eboard-ready ] || [ "$waited" -ge 90 ]; do
    sleep 1
    waited=$((waited + 1))
done

while :; do
    if [ -x "$kpython" ]; then
        note "Klippy is starting..."
        "$kpython" "$kroot/klipper/klippy/klippy.py" "$kroot/config/printer.cfg" -l "$kroot/logs/printer.log" -a /tmp/uds
        note "Klippy exited; see $kroot/logs/printer.log. Restarting in 3 s."
        note "ERR CODE 0 - Klippy"
    fi
    sleep 3
done
