#!/bin/sh
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
# Made for the OpenAD5X project
# This file may be distributed under the terms of the MIT license.
#
# Starts the GrumpyScreen touch UI and restarts it whenever it stops.

screen_bin=/usr/data/grumpyscreen/grumpyscreen
touch_ko=/module_driver/tsc2007_touch.ko
touch_done=/tmp/openad5x-touch
kcfg=/usr/data/openad5x/klipper/config
ui_base=/usr/data/openad5x/grumpyscreen/grumpyscreen.cfg
ui_user=$kcfg/grumpyscreen.ini

[ -x "$screen_bin" ] || exit 0

# GrumpyScreen takes the touch driver's coordinates as pixels and has no
# calibration of its own, so once per boot the tsc2007 driver is reloaded
# to report 0..800 x 0..480 across the panel's measured touch area
# (falling back to the full 0..4096 range if that load fails).
tsc_common="tsc_irq_gpio=PC07 tsc_power_on_gpio=-1 tsc_regulator_name=-1 tsc_i2c_bus=0 tsc_i2c_addr=0x48 tsc_x_plate_ohms=660 tsc_max_rt=600 tsc_fuzzx=0 tsc_fuzzy=0 tsc_fuzzz=0 tsc_poll_period=0 tsc_xy_coords_exchange=0 tsc_x_coords_flip=0 tsc_y_coords_flip=1 tsc_x_coords_max=800 tsc_y_coords_max=480"
if [ ! -f "$touch_done" ] && [ -f "$touch_ko" ]; then
    rmmod tsc2007_touch 2>/dev/null
    if ! insmod "$touch_ko" $tsc_common tsc_x_actrue_min=309 tsc_x_actrue_max=3765 tsc_y_actrue_min=705 tsc_y_actrue_max=3447; then
        insmod "$touch_ko" $tsc_common tsc_x_actrue_min=0 tsc_x_actrue_max=4096 tsc_y_actrue_min=0 tsc_y_actrue_max=4096
    fi
    touch "$touch_done"
    sleep 1
fi

# first input device whose name mentions goodix or touch
touch_dev=$(awk '
    /^N: Name=/ { dev = tolower($0) }
    /^H: Handlers=/ && dev ~ /goodix|touch/ {
        for (f = 2; f <= NF; f++) {
            if ($f ~ /^event[0-9]+$/) { print "/dev/input/" $f; exit }
        }
    }' /proc/bus/input/devices 2>/dev/null)
[ -n "$touch_dev" ] || touch_dev=/dev/input/event1
export LVGL_EVDEV_DEV="$touch_dev"

# the AD5X panel needs no rotation
export DISPLAY_ROTATE=0

# grumpyscreen.cfg holds the shipped settings (updated with OpenAD5X);
# grumpyscreen.ini in the config folder holds the user's own, and can be
# edited from Fluidd or Mainsail.
[ -f "$ui_base" ] && export CONFIG_FILE="$ui_base"

# writes "key: value" under [ui] in the user file unless already there
ui_set() {
    grep -q '^\[ui\]' "$ui_user" || printf '\n[ui]\n' >> "$ui_user"
    grep -q "^$1: $2\$" "$ui_user" && return
    sed -i "/^$1:/d" "$ui_user"
    sed -i "/^\[ui\]/a $1: $2" "$ui_user"
}

if [ -d "$kcfg" ]; then
    [ -f "$ui_user" ] || printf '[ui]\n' > "$ui_user"
    export CONFIG_OVERRIDE_FILE="$ui_user"
    # checked every boot: Spoolman button needs [spoolman] in
    # moonraker.conf, the MMU panel needs AFC included in printer.cfg
    spool_hidden=true
    grep -q '^\[spoolman\]' "$kcfg/moonraker.conf" 2>/dev/null && spool_hidden=false
    ui_set hide_spoolman $spool_hidden
    mmu_hidden=true
    grep -q '^\[include AFC/' "$kcfg/printer.cfg" 2>/dev/null && mmu_hidden=false
    ui_set hide_mmu $mmu_hidden
fi

(
    while :; do
        "$screen_bin" >> /usr/data/logs/grumpyscreen.log 2>&1
        sleep 3
    done
) &
echo "started"
