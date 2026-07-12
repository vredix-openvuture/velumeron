#!/usr/bin/env bash
# Velumeron – manual night-light toggle (settings home hub).
#
# Runs wlsunset pinned to "night" almost the whole day (sunrise 00:00, sunset
# 00:01) so the warm temperature applies immediately instead of following the
# real sun times. State is simply whether a wlsunset process is running, so it
# survives shell restarts.
#
#   nightlight.sh --active   # print "on" | "off" (settings toggle state)
#   nightlight.sh --on
#   nightlight.sh --off
#   nightlight.sh --toggle   # (default)

TEMP=4000

_running() { pgrep -x wlsunset >/dev/null; }
_on()  { _running || setsid -f wlsunset -t "$TEMP" -T 6500 -S 00:00 -s 00:01 >/dev/null 2>&1; }
_off() { pkill -x wlsunset 2>/dev/null; }

case "${1:---toggle}" in
    --active) _running && echo on || echo off ;;
    --on)     _on ;;
    --off)    _off ;;
    *)        if _running; then _off; else _on; fi ;;
esac
