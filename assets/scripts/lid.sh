#!/usr/bin/env bash
# Laptop lid handling for the native quickshell lockscreen. Bound from
# hypr.lua/modules/devices.lua (switch:on / switch:off on "Lid Switch", { locked = true }):
#
#   close → lock the session now + arm a cancelable suspend after LID_SUSPEND_DELAY (default 2 min)
#   open  → cancel the pending suspend (screen is already locked; re-lock is a no-op if so)
#
# The suspend runs from a backgrounded subshell whose PID is stashed in $FLAG; `open` (or a second
# `close`) kills it, which stops the suspend from ever firing. It goes through suspend.sh so the
# lockscreen is guaranteed drawn first (here it long since is — the lid locked 2 min earlier).
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

FLAG="${XDG_RUNTIME_DIR:-/tmp}/velumeron-lid-suspend.pid"
LID_SUSPEND_DELAY="${LID_SUSPEND_DELAY:-120}"   # seconds

lock()   { qs -p "$VELUMERON_DIR/quickshell" ipc call lock lock 2>/dev/null; }
cancel() { [[ -f "$FLAG" ]] && { kill "$(cat "$FLAG")" 2>/dev/null; rm -f "$FLAG"; }; }

case "${1:-}" in
    close)
        cancel
        lock
        ( sleep "$LID_SUSPEND_DELAY" && "$VELUMERON_DIR/assets/scripts/suspend.sh" ) &
        echo $! > "$FLAG"
        ;;
    open)
        cancel
        lock
        ;;
    *)
        echo "usage: lid.sh {close|open}" >&2
        exit 1
        ;;
esac
