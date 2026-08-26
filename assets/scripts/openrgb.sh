#!/usr/bin/env bash
# openrgb.sh — the shell's control surface for OpenRGB.
#
# OpenRGB already owns the hard part: you build a lighting profile in ITS editor, where you can see
# every zone of every device. What it does not own is the desktop — so a profile you made lives in
# a file you have to remember to load, and nothing loads it at login. That is the gap this fills:
#
#   list            profiles you have saved, as JSON
#   status          installed / running / server up / profiles / the one we applied last
#   apply <name>    load a profile now  (and remember it as the active one)
#   start | stop    the SDK server, minimised — the daemon the shell talks to
#   devices         controllers OpenRGB can see, as JSON
#   boot            what the session runs at login: the startup profile, if one is set
#
# Profiles are plain files: $OPENRGB_DIR/<name>.orp. Nothing here writes them — creating and
# editing profiles stays in OpenRGB, which is the tool that can actually show you a keyboard.
set -uo pipefail

_dir="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$_dir/lib/env.sh"

OPENRGB_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/OpenRGB"
SETTINGS="$VELUMERON_USER_DIR/gui/settings.json"
ACTIVE_FILE="$VELUMERON_USER_DIR/gui/openrgb-active"
PORT=6742

have()      { command -v openrgb >/dev/null 2>&1; }
running()   { pgrep -x openrgb >/dev/null 2>&1; }
server_up() { ss -ltn 2>/dev/null | grep -q ":${PORT}\b"; }

# A setting, straight from the shell's settings.json (the panel writes it, we read it).
setting() {  # $1 key, $2 default
    local v=""
    [[ -f "$SETTINGS" ]] && command -v jq >/dev/null 2>&1 &&
        v=$(jq -r --arg k "$1" '.[$k] // empty' "$SETTINGS" 2>/dev/null)
    printf '%s' "${v:-$2}"
}

profiles() {  # one name per line, newest-modified last
    [[ -d "$OPENRGB_DIR" ]] || return 0
    local f n
    for f in "$OPENRGB_DIR"/*.orp; do
        [[ -e "$f" ]] || continue
        n="$(basename "$f" .orp)"
        # OpenRGB's own backup churn (foo.orp.orp, foo.orp.bak-…) is not a profile you made.
        [[ "$n" == *.orp ]] && continue
        printf '%s\n' "$n"
    done | sort
}

json_array() { python3 -c 'import json,sys; print(json.dumps([l for l in sys.stdin.read().split("\n") if l]))'; }

case "${1:-status}" in

    list) profiles | json_array ;;

    status)
        have      && inst=true || inst=false
        running   && run=true  || run=false
        server_up && srv=true  || srv=false
        act=""; [[ -f "$ACTIVE_FILE" ]] && act="$(<"$ACTIVE_FILE")"
        python3 -c '
import json, sys
inst, run, srv, act = sys.argv[1] == "true", sys.argv[2] == "true", sys.argv[3] == "true", sys.argv[4]
print(json.dumps({"installed": inst, "running": run, "server": srv, "active": act,
                  "profiles": [l for l in sys.stdin.read().split("\n") if l]}))' \
            "$inst" "$run" "$srv" "$act" <<< "$(profiles)"
        ;;

    devices)
        have || { echo "[]"; exit 0; }
        # `--list-devices` prints a numbered block per controller; only the names are wanted here.
        openrgb --list-devices 2>/dev/null |
            sed -n 's/^[0-9]\+: \(.*\)$/\1/p' | json_array
        ;;

    start)
        have || { echo "openrgb is not installed" >&2; exit 1; }
        running && exit 0
        setsid -f openrgb --server --startminimized >/dev/null 2>&1
        for _ in $(seq 1 30); do server_up && break; sleep 0.5; done
        ;;

    stop)  pkill -x openrgb >/dev/null 2>&1; exit 0 ;;

    apply)
        have || { echo "openrgb is not installed" >&2; exit 1; }
        name="${2:-}"; [[ -n "$name" ]] || { echo "usage: openrgb.sh apply <profile>" >&2; exit 2; }
        [[ -f "$OPENRGB_DIR/$name.orp" ]] || { echo "no such profile: $name" >&2; exit 1; }
        # A profile can only be loaded into a running instance; without one, `openrgb -p` starts a
        # short-lived process, applies, and exits — which is fine, but then nothing holds the SDK
        # server for the next call. So make sure the daemon is up first.
        running || "$0" start
        openrgb -p "$name" >/dev/null 2>&1 || { echo "profile load failed" >&2; exit 1; }
        mkdir -p "$(dirname "$ACTIVE_FILE")"; printf '%s' "$name" > "$ACTIVE_FILE"
        ;;

    boot)
        # Login path. Silent and non-fatal throughout: RGB is decoration, and a machine whose
        # controller did not enumerate this boot must still get a desktop.
        have || exit 0
        [[ "$(setting openrgb_enabled false)"  == true ]] || exit 0
        prof="$(setting openrgb_profile "")"
        [[ -n "$prof" ]] || exit 0
        # Always through openrgb-restore.sh: on most machines it is a plain "server up, then load",
        # and on the ones that need the ARGB zone-size fix that fix HAS to happen before the load.
        # The script decides which of the two it is; it never fails the login either way.
        exec bash "$_dir/openrgb-restore.sh" "$prof"
        ;;

    *)
        echo "usage: openrgb.sh {status|list|devices|apply <profile>|start|stop|boot}" >&2; exit 2 ;;
esac
