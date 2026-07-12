#!/usr/bin/env bash
# resume-wake.sh — hypridle's after_sleep_cmd. A single dpms-on at resume can fire
# while the outputs are still re-initializing (DP link training takes seconds) and
# silently no-op — the session is then alive but every display stays dark. Retry
# until the compositor reports all monitors as powered, then reapply the cursor
# so the first frame isn't a stale hardware cursor.
_powered=0
for _ in 1 2 3 4 5 6; do
    hyprctl dispatch 'hl.dsp.dpms("on")' >/dev/null 2>&1
    sleep 2
    if ! hyprctl monitors -j 2>/dev/null | grep -q '"dpmsStatus": *false'; then
        _powered=1
        break
    fi
done
[[ $_powered -eq 1 ]] || logger -t velumeron-idle "resume-wake: displays still report dpms off after retries" 2>/dev/null || true

# Resume can shuffle persistent workspaces onto the wrong output even though the
# connectors never report a drop — so monitor.added never fires and the reconnect
# hook in modules/workspaces.lua can't help (ws1 woke up on DP-3, 2026-07-11).
# Re-home them once the outputs are powered. Per-monitor (only_mon) calls only
# MOVE workspaces, they never re-focus — no focus stealing right after wake.
hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
try:
    for m in json.load(sys.stdin):
        print(m["name"])
except Exception:
    pass
' | while read -r _mon; do
    [[ -n "$_mon" ]] && hyprctl eval "VTL_rehome_workspaces(\"$_mon\")" >/dev/null 2>&1
done
