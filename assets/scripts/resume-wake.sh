#!/usr/bin/env bash
# resume-wake.sh — hypridle's after_sleep_cmd. A single dpms-on at resume can fire
# while the outputs are still re-initializing (DP link training takes seconds) and
# silently no-op — the session is then alive but every display stays dark. Retry
# until the compositor reports all monitors as powered, then reapply the cursor
# so the first frame isn't a stale hardware cursor.
for _ in 1 2 3 4 5 6; do
    hyprctl dispatch 'hl.dsp.dpms("on")' >/dev/null 2>&1
    sleep 2
    if ! hyprctl monitors -j 2>/dev/null | grep -q '"dpmsStatus": *false'; then
        exit 0
    fi
done
logger -t velumeron-idle "resume-wake: displays still report dpms off after retries" 2>/dev/null || true
