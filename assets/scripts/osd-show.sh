#!/usr/bin/env bash
# Velumeron – OSD trigger client → quickshell "osd" IPC handler.
#
#   osd-show.sh volume          # show the live sink volume
#   osd-show.sh brightness 80   # show the given percent
#
# No-op (never blocks) if quickshell isn't running.

set -u
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

QS_DIR="$VELUMERON_DIR/quickshell"

case "${1:-}" in
    volume)     timeout 0.4 qs -p "$QS_DIR" ipc call osd volume               2>/dev/null || true ;;
    brightness) timeout 0.4 qs -p "$QS_DIR" ipc call osd brightness "${2:-0}" 2>/dev/null || true ;;
esac
