#!/bin/sh
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
# Made for the OpenAD5X project
# This file may be distributed under the terms of the MIT license.
#
# Stops GrumpyScreen; 40-grumpyscreen.sh starts it again within 3 s.

pids=$(pidof grumpyscreen)
[ -n "$pids" ] && kill $pids
