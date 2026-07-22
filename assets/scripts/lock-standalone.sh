#!/usr/bin/env bash
# Velumeron — STANDALONE lockscreen (Tier-0 à-la-carte).
#
# Runs the native quickshell lockscreen as its OWN instance, next to a user's own
# bar / compositor config — no full velumeron shell, no hypr.lua, no services.
# Engagement stays compositor-agnostic (loginctl → logind → hypridle → IPC), so
# this works on Hyprland, sway, niri … anything speaking ext-session-lock.
#
#   lock-standalone.sh start    # launch the (invisible) lock daemon
#   lock-standalone.sh lock     # engage the lock  ← wire this into your hypridle lock_cmd
#   lock-standalone.sh stop     # stop the daemon
#   lock-standalone.sh status
#
# BYO wiring — in YOUR hypridle.conf:
#     lock_cmd         = /path/to/lock-standalone.sh lock
#     before_sleep_cmd = loginctl lock-session
# and start the daemon from your compositor autostart:
#     exec-once = /path/to/lock-standalone.sh start   (Hyprland)
#     exec       /path/to/lock-standalone.sh start    (sway)
#
# See docs/standalone-lockscreen.md for fonts + PAM notes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
# env.sh resolves VELUMERON_DIR from this script's location and VELUMERON_USER_DIR
# with a ~/.config/velumeron fallback. NEITHER needs to be velumeron-provisioned —
# the lock's visuals degrade to defaults when settings.json / colors.json are absent.
source "$SCRIPT_DIR/lib/env.sh"

ROOT="$VELUMERON_DIR/quickshell/lock-standalone.qml"
QS_BIN="$(command -v qs || command -v quickshell || true)"
LOG="${XDG_RUNTIME_DIR:-/tmp}/velumeron-lock-standalone.log"

if [[ -z "$QS_BIN" ]]; then
    echo "error: quickshell (qs) not found in PATH" >&2; exit 1
fi
if [[ ! -f "$ROOT" ]]; then
    echo "error: lock root not found: $ROOT" >&2; exit 1
fi

# Match the daemon by its unique config-root filename, so we never touch the user's
# own quickshell / the full velumeron shell (a different config path).
_running() { pgrep -f "lock-standalone.qml" >/dev/null 2>&1; }

case "${1:-}" in
    start)
        if _running; then echo "lock daemon already running"; exit 0; fi
        # The mpv wallpaper plugin isn't used by the lock, but exposing the plugins dir
        # is harmless and keeps the config dir's qmldir resolvable if anything references it.
        export QML_IMPORT_PATH="$VELUMERON_DIR/quickshell/plugins${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
        VELUMERON_DIR="$VELUMERON_DIR" VELUMERON_USER_DIR="$VELUMERON_USER_DIR" \
            setsid -f "$QS_BIN" -p "$ROOT" >"$LOG" 2>&1
        echo "lock daemon started (root: $ROOT, log: $LOG)"
        ;;
    lock)
        # Engage. `qs ipc call` connects to the instance launched with the SAME -p path.
        exec "$QS_BIN" -p "$ROOT" ipc call lock lock
        ;;
    stop)
        if _running; then pkill -f "lock-standalone.qml" 2>/dev/null; echo "lock daemon stopped"
        else echo "not running"; fi
        ;;
    status)
        if _running; then echo "up"; else echo "down"; fi
        ;;
    *)
        echo "usage: lock-standalone.sh start|lock|stop|status" >&2; exit 2 ;;
esac
