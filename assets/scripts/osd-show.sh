#!/usr/bin/env bash
# Vutureland – OSD trigger client.
# Writes a one-line message to the OSD daemon's FIFO so it shows the banner.
#
#   osd-show.sh volume          # daemon reads the live sink volume
#   osd-show.sh brightness 80   # daemon shows the given percent
#
# No-op (never blocks) if the daemon isn't running.

FIFO="${XDG_RUNTIME_DIR:-/tmp}/vutureland-osd.fifo"
[ -p "$FIFO" ] || exit 0

# Short timeout guards against a stale FIFO with no reader (daemon gone).
timeout 0.3 sh -c 'printf "%s\n" "$1" > "$2"' _ "$*" "$FIFO" 2>/dev/null || true
