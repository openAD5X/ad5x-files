#!/bin/sh
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
# Made for the OpenAD5X project
# This file may be distributed under the terms of the MIT license.
#
# Runs Moonraker (installed in /usr/prog/moonraker) with the OpenAD5X
# components and starts it again whenever it stops.

msg_file=/tmp/openad5x.log
data_dir=/usr/data/openad5x/klipper
mr_root=/usr/prog/moonraker/moonraker
mr_python=/usr/prog/moonraker/moonraker-env/bin/python
our_components=/usr/data/openad5x/moonraker
mr_conf=$data_dir/config/moonraker.conf
export PATH=$PATH:/opt/bin

# Settings for pip when Moonraker's update manager installs packages:
# zeroconf without Cython, Pillow built against python-hf's zlib/libjpeg,
# and a cache of its own (Entware's soft-float wheels use the same tag).
export SKIP_CYTHON=1
export CFLAGS="-I/usr/data/python-hf/include"
export LDFLAGS="-L/usr/data/python-hf/lib"
export PIP_CACHE_DIR=/usr/data/openad5x/home/.cache/pip-hf
# at boot HOME is the read-only root; pip needs somewhere writable
if [ -z "${HOME:-}" ] || [ "$HOME" = / ]; then
    export HOME=/usr/data/openad5x/home
    mkdir -p "$HOME"
fi

note() {
    echo "$1" >> "$msg_file"
}

[ -x "$mr_python" ] || exit 0

for comp in openad5x_3mf openad5x_machine; do
    rel="/moonraker/components/$comp.py"
    ln -sf "$our_components/$comp.py" "$mr_root$rel"
    # hide the link from git so the update manager doesn't call the repo dirty
    if [ -d "$mr_root/.git" ]; then
        excl="$mr_root/.git/info/exclude"
        mkdir -p "$mr_root/.git/info"
        if ! grep -qx "$rel" "$excl" 2>/dev/null; then
            echo "$rel" >> "$excl"
        fi
    fi
    if ! grep -q "^\[$comp\]" "$mr_conf"; then
        printf '\n[%s]\n' "$comp" >> "$mr_conf"
    fi
done

scratch=$data_dir/tmp
mkdir -p "$scratch"

while :; do
    note "Launching Moonraker..."
    rm -rf "$scratch"/*
    TMPDIR="$scratch" "$mr_python" "$mr_root/moonraker/moonraker.py" -d "$data_dir"
    note "Moonraker exited; restarting in 3 s."
    note "ERR CODE 1 - Moonraker"
    sleep 3
done
