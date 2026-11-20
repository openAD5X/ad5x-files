#!/bin/sh
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
# Made for the OpenAD5X project
# This file may be distributed under the terms of the MIT license.
#
# Gives Fluidd the OpenAD5X macro layout (fluidd/macros.json) when no
# layout has been saved yet. A layout the user saved is left alone.

layout=/usr/data/openad5x/fluidd/macros.json
moonraker=http://127.0.0.1:7125
db_item=$moonraker/server/database/item
# Entware's curl; the stock one found first on the boot PATH needs other libraries
http=/opt/bin/curl
export PATH=$PATH:/opt/bin
# the LD_LIBRARY_PATH inherited from FlashForge's startup has an old
# libcurl that breaks Entware's curl (undefined symbol curl_mime_free)
unset LD_LIBRARY_PATH

[ -f "$layout" ] || exit 0

# wait for Moonraker: 120 checks, 5 s apart
checks=0
while ! "$http" -fs "$moonraker/server/info" >/dev/null 2>&1; do
    checks=$((checks + 1))
    [ "$checks" -ge 120 ] && exit 0
    sleep 5
done

# Fluidd stores an empty object ("value":{}) by itself, which counts as unset
if current=$("$http" -fs "$db_item?namespace=fluidd&key=macros" 2>/dev/null); then
    if ! printf '%s' "$current" | grep -q '"value": *{}'; then
        exit 0
    fi
fi

{
    printf '{"namespace":"fluidd","key":"macros","value":'
    cat "$layout"
    printf '}'
} | "$http" -fs -X POST -H 'Content-Type: application/json' -d @- "$db_item" >/dev/null
