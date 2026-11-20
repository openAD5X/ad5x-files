#!/bin/sh
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
# Made for the OpenAD5X project
# This file may be distributed under the terms of the MIT license.
#
# The eboard (/dev/ttyS5) powers up in its bootloader, which prints "Ready"
# at 115200 baud and waits for an 'A' (0x41) before it starts the
# application, answering with ACK (0x06).
#
# Part 1, at boot: start the eboard application (flashing it first if
# /usr/data/kalico-fw/eboard.flash names a .hex), then create
# /tmp/openad5x-eboard-ready, which 10-klipper.sh waits for.
#
# Part 2, afterwards: follow Klipper's log; when it reports
# "mcu 'eboard': Timeout on connect" the board is back in its bootloader
# (power glitch, FIRMWARE_RESTART), so Klippy is paused and the board is
# woken again. Only the eboard has this boot stage: ttyS2 (mainboard)
# boots straight into its application and ttyS4 (IFS, RS485) uses XMODEM.

wake_log=/usr/data/logs/mcu-wake.log
klipper_log=/usr/data/openad5x/klipper/logs/printer.log
lock_file=/tmp/mcu-wake.lock
min_gap=7

eb_tty=/dev/ttyS5
eb_flash_req=/usr/data/kalico-fw/eboard.flash
eb_ready_flag=/tmp/openad5x-eboard-ready
flash_log_dir=/usr/data/logs/openad5x
iap_tool=$(ls -d /usr/prog/PROGRAM/control/[0-9]* 2>/dev/null | sort | tail -n 1)/IAPCommand

# one copy only
exec 9>"$lock_file"
flock -n 9 || exit 0

ACK_BYTE=$(printf '\006')
# Klipper identify request; the reply frame ends with 0x7e
IDENT_FRAME='\176\010\020\001\000\050\136\237\176'
paused_pids=

say() {
    echo "$(date '+%F %T') $*" >> "$wake_log"
}

# prints "<tty> <klipper baud> <parity to try first> <parity to try next>"
board_line() {
    [ "$1" = eboard ] || return 1
    echo "/dev/ttyS5 230400 N E"
}

find_klippy() {
    for p in /proc/[0-9]*; do
        if tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -q 'klippy/klippy\.py'; then
            echo "${p#/proc/}"
        fi
    done
}

pause_klippy() {
    paused_pids=$(find_klippy)
    [ -n "$paused_pids" ] && kill -STOP $paused_pids
}

unpause_klippy() {
    [ -n "$paused_pids" ] && kill -CONT $paused_pids 2>/dev/null
    paused_pids=
}

# port, baud, parity (N or E)
line_setup() {
    case "$3" in
        E) parity_flags="parenb -parodd" ;;
        *) parity_flags="-parenb" ;;
    esac
    stty -F "$1" "$2" raw -echo cs8 -cstopb -crtscts clocal cread -inpck $parity_flags
}

# Watches fd 3 for up to 4 s. heard=1 if any byte came in.
# Returns 0 as soon as "Ready" has been received.
await_ready() {
    heard=0
    window=
    stop_at=$(($(date +%s) + 4))
    while [ "$(date +%s)" -lt "$stop_at" ]; do
        ch=
        IFS= read -r -n 1 -t 0.2 ch <&3 || [ -n "$ch" ] || continue
        heard=1
        window="$window$ch"
        case "$window" in *Ready*) return 0 ;; esac
        if [ ${#window} -gt 16 ]; then
            window=${window#????????}
        fi
    done
    return 1
}

# Returns 0 when byte $1 is read from fd 3. Gives up after six empty
# 0.05 s reads in a row or 256 bytes.
expect_byte() {
    quiet=0
    count=0
    while [ "$quiet" -lt 6 ] && [ "$count" -lt 256 ]; do
        ch=
        if IFS= read -r -n 1 -t 0.05 ch <&3 || [ -n "$ch" ]; then
            count=$((count + 1))
            [ "$ch" = "$1" ] && return 0
        else
            quiet=$((quiet + 1))
        fi
    done
    return 1
}

# up to three 'A's, each followed by a wait for ACK
release_bootloader() {
    for attempt in 1 2 3; do
        printf A >&3
        expect_byte "$ACK_BYTE" && return 0
    done
    return 1
}

# Is the application already answering? Empty the input, send identify,
# wait for the closing '~'.
app_answers() {
    drained=0
    while [ "$drained" -lt 256 ] && IFS= read -r -n 1 -t 0.05 ch <&3; do
        drained=$((drained + 1))
    done
    printf "$IDENT_FRAME" >&3
    expect_byte "~"
}

# name tty klipper_baud parity...
rewake() {
    mcu=$1
    port=$2
    app_baud=$3
    shift 3
    pause_klippy
    old_settings=$(stty -g -F "$port") || { unpause_klippy; return; }
    exec 3<>"$port"
    outcome="failed: no banner"
    for par in "$@"; do
        line_setup "$port" 115200 "$par"
        if await_ready; then
            if release_bootloader; then
                outcome="ok (parity $par)"
                break
            fi
            line_setup "$port" "$app_baud" N
            if app_answers; then
                outcome="ok (parity $par, ack lost)"
                break
            fi
            outcome="failed: no ack"
        fi
        # silence on this parity means the board is not talking at all
        [ "$heard" = 1 ] || break
    done
    exec 3<&-
    stty -F "$port" "$old_settings"
    unpause_klippy
    say "$mcu: wake $outcome"
}

eb_port_115200() {
    stty -F $eb_tty 115200 cs8 -parenb -cstopb -crtscts clocal raw -echo
}

# Flashes the requested .hex with IAPCommand. The request file is
# removed only after a successful write.
eb_flash() {
    hexfile=$(cat "$eb_flash_req")
    mkdir -p $flash_log_dir
    say "eboard: flashing $hexfile"
    $iap_tool "$hexfile" $eb_tty > $flash_log_dir/eboard-flash.log 2>&1
    say "eboard: IAPCommand exit $?"
    if grep -q 'STM32Write: success' $flash_log_dir/eboard-flash.log; then
        rm -f "$eb_flash_req"
    else
        say "eboard: flash failed, tried again at the next power-on"
    fi
}

eb_boot() {
    eb_port_115200 || return 1
    exec 3<>$eb_tty
    rounds=0
    did_flash=
    while [ "$rounds" -lt 20 ]; do
        # up to ten 1 s line reads for the banner
        saw_ready=
        n=0
        while [ "$n" -lt 10 ]; do
            if IFS= read -r -t 1 text <&3; then
                case "$text" in *Ready*) saw_ready=1; break ;; esac
            fi
            n=$((n + 1))
        done
        if [ -z "$saw_ready" ]; then
            say "eboard: no Ready, application already running"
            exec 3<&-
            return 0
        fi
        # IAPCommand only works while the bootloader waits for 'A';
        # one flash attempt per boot
        if [ -f "$eb_flash_req" ] && [ -z "$did_flash" ]; then
            did_flash=1
            exec 3<&-
            eb_flash
            eb_port_115200
            exec 3<>$eb_tty
            continue
        fi
        printf '\101' >&3
        n=0
        while [ "$n" -lt 20 ]; do
            if IFS= read -r -n 1 -t 1 ch <&3 && [ "$ch" = "$ACK_BYTE" ]; then
                say "eboard: application started"
                exec 3<&-
                return 0
            fi
            n=$((n + 1))
        done
        rounds=$((rounds + 1))
    done
    say "eboard: no ACK"
    exec 3<&-
    return 1
}

rm -f "$eb_ready_flag"
eb_boot
touch "$eb_ready_flag"

say "started"
tail -n 0 -F "$klipper_log" 2>/dev/null | {
    trap 'unpause_klippy; exit' INT TERM HUP
    while IFS= read -r entry; do
        case "$entry" in
            *"mcu '"*"': Timeout on connect"*) ;;
            *) continue ;;
        esac
        mcu=${entry#*mcu \'}
        mcu=${mcu%%\'*}
        spec=$(board_line "$mcu") || continue
        eval "prev=\${tried_$mcu:-0}"
        now=$(date +%s)
        [ $((now - prev)) -lt $min_gap ] && continue
        say "$mcu: identify unanswered"
        rewake "$mcu" $spec
        eval "tried_$mcu=$(date +%s)"
    done
}
