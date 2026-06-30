#!/usr/bin/env bash
# Apply the wallust colour mode chosen in the GUI / corner menu.
#
#   apply-theme.sh auto
#   apply-theme.sh fixed <scheme.json>
#
# Mirrors gui/pages/wallust.py (WallustPage._on_apply + _run_hooks), but reloads
# whichever bar backend is active (waybar OR quickshell) instead of always waybar.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

MODE_FILE="$VELUMERON_USER_DIR/wallust/color-mode"
FIXED_DIR="$VELUMERON_DIR/wallust/fixed_colors"
WALLUST_CFG="$VELUMERON_DIR/wallust"

mode="${1:-auto}"
mkdir -p "$(dirname "$MODE_FILE")"

if [[ "$mode" != "fixed" || -z "${2:-}" ]]; then
    # Automatic: just record the mode. Colours are re-derived on the next
    # wallpaper change (handled by wallpaper-set.sh), exactly like the old GUI.
    printf 'auto\n' > "$MODE_FILE"
    exit 0
fi

scheme="$2"
scheme_path="$FIXED_DIR/$scheme"
if [[ ! -f "$scheme_path" ]]; then
    echo "apply-theme: scheme not found: $scheme_path" >&2
    exit 1
fi

printf 'fixed:%s\n' "$scheme" > "$MODE_FILE"

# Generate the palette from the fixed scheme. `wallust cs` skips the configured
# [hooks], so run the post-processing steps ourselves (same as the old GUI).
wallust --config-dir "$WALLUST_CFG" cs "$scheme_path"

bash "$VELUMERON_DIR/assets/scripts/wallust/hyprland_lua-colors.sh" 2>/dev/null || true
hyprctl reload                  >/dev/null 2>&1 || true
pywalfox update                 >/dev/null 2>&1 || true

# Reload the active bar backend. Detached into its own session so that, when the
# quickshell backend restarts itself, killing the old instance can't abort us.
setsid bash "$VELUMERON_DIR/assets/scripts/launch-shell.sh" </dev/null >/dev/null 2>&1 &

exit 0
