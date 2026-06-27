#!/usr/bin/env bash
# Vutureland — Bar launcher
# Reads shell_backend from gui/settings.json and delegates to the matching script.
# Defaults to waybar when the setting is absent or jq is unavailable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

SETTINGS="$VUTURELAND_USER_DIR/gui/settings.json"
BACKEND="waybar"

if [[ -f "$SETTINGS" ]] && command -v jq >/dev/null 2>&1; then
    BACKEND=$(jq -r '.shell_backend // "waybar"' "$SETTINGS" 2>/dev/null || echo "waybar")
fi

case "$BACKEND" in
    quickshell) exec bash "$SCRIPT_DIR/launch-quickshell.sh" ;;
    *)          exec bash "$SCRIPT_DIR/launch-waybar.sh"     ;;
esac
