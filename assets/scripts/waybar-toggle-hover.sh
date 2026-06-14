#!/usr/bin/env bash
# Vutureland – instantly toggle Waybar visibility via SIGUSR1.
# Kills the hover daemon first so it doesn't fight the manual toggle.
# The flag file (.hover-hide) is left untouched; the next waybar restart
# restores the user's preferred auto-hide setting.

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

pkill -f "$SCRIPT_DIR/waybar-hover.sh" 2>/dev/null || true
pkill -SIGUSR1 -x waybar 2>/dev/null || true
