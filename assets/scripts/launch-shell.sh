#!/usr/bin/env bash
# Velumeron — Shell launcher.
# The shell is QuickShell (waybar/swaync/the Python GUI are archived). Kept as a
# stable indirection so autostart.lua and wallust hooks don't need to change if
# the backend ever does again.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

exec bash "$SCRIPT_DIR/launch-quickshell.sh"
