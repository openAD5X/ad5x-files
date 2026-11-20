#!/bin/sh
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
# Made for the OpenAD5X project
# This file may be distributed under the terms of the MIT license.
#
# Gives SSH working SFTP. The stock dropbear looks for
# /usr/libexec/sftp-server, which the read-only root file system lacks.
# A copy of dropbear is made with that path changed to
# /opt/libexec/sftp-server (Entware, same length), bind-mounted over
# the stock binary, and dropbear is restarted.

msg_file=/tmp/openad5x.log
entware_sftp=/opt/libexec/sftp-server
dropbear_bin=/usr/sbin/dropbear
patched_bin=/usr/data/openad5x/bin/dropbear-sftp

note() {
    echo "$1" >> "$msg_file"
}

find_strings() {
    strings "$@" 2>/dev/null || busybox strings "$@"
}

# /opt is mounted by 05-entfix.sh, which runs at the same time
waited=0
until [ -x "$entware_sftp" ] || [ "$waited" -ge 60 ]; do
    sleep 1
    waited=$((waited + 1))
done
if [ ! -x "$entware_sftp" ]; then
    note "SFTP: $entware_sftp missing (opkg install openssh-sftp-server)"
    exit 0
fi

# already done this boot
if grep -q " $dropbear_bin " /proc/mounts; then
    exit 0
fi

offset=$(find_strings -t d "$dropbear_bin" |
    sed -n 's#^ *\([0-9]*\) /usr/libexec/sftp-server$#\1#p' | head -n 1)
if [ -z "$offset" ]; then
    note "SFTP: dropbear has no sftp-server path to patch"
    exit 0
fi

work="$patched_bin.tmp"
mkdir -p "$(dirname "$patched_bin")"
cp "$dropbear_bin" "$work" || exit 0
# overwrite "/usr" with "/opt" in place
printf /opt | dd of="$work" bs=1 seek="$offset" conv=notrunc 2>/dev/null

size_ok=0
[ "$(wc -c < "$work")" = "$(wc -c < "$dropbear_bin")" ] && size_ok=1
if [ "$size_ok" = 1 ] &&
    find_strings -t d "$work" | grep -q "^ *$offset /opt/libexec/sftp-server$"; then
    chmod 755 "$work" &&
    mv "$work" "$patched_bin"
else
    rm -f "$work"
    note "SFTP: could not patch dropbear"
    exit 0
fi

mount --bind "$patched_bin" "$dropbear_bin" || exit 0
/etc/init.d/S50dropbear restart >/dev/null 2>&1
note "SFTP enabled"
