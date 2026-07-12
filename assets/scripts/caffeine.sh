#!/usr/bin/env bash
# Velumeron – keep-awake toggle (settings home hub).
#
# Holds a systemd idle inhibitor while on: hypridle honors systemd-inhibit
# --what=idle by default (ignore_systemd_inhibit is unset in hypridle.conf),
# so the idle→lock and idle→suspend listeners stop firing. State is whether
# the tagged inhibitor process is running, so it survives shell restarts.
#
#   caffeine.sh --active   # print "on" | "off" (settings toggle state)
#   caffeine.sh --on
#   caffeine.sh --off
#   caffeine.sh --toggle   # (default)

TAG="velumeron-caffeine"

# The [-] classes stop this pattern from matching a SIBLING pgrep's own argv: the settings hub
# exists once per monitor and they poll --active concurrently — with a plain pattern each pgrep
# saw the other pgrep's command line and every monitor reported a phantom "on".
_pids() { pgrep -f "systemd[-]inhibit.*--why=velumeron[-]caffeine"; }
_on()   { [[ -n "$(_pids)" ]] || setsid -f systemd-inhibit --what=idle --who=velumeron --why="$TAG" sleep infinity >/dev/null 2>&1; }
# setsid made systemd-inhibit a session leader — kill the whole session so the
# inner `sleep infinity` doesn't linger as an orphan.
_off()  { for sid in $(_pids); do pkill -s "$sid" 2>/dev/null; done }

case "${1:---toggle}" in
    --active) [[ -n "$(_pids)" ]] && echo on || echo off ;;
    --on)     _on ;;
    --off)    _off ;;
    *)        if [[ -n "$(_pids)" ]]; then _off; else _on; fi ;;
esac
