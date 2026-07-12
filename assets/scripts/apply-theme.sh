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
    # Automatic: record the mode then immediately re-derive from the current wallpaper
    # so that changes to wallust options (palette, backend, …) take effect right away.
    printf 'auto\n' > "$MODE_FILE"
    _wp=$(python3 - "$VELUMERON_USER_DIR" <<'PY' 2>/dev/null || echo ""
import json, os, sys
d = os.path.join(sys.argv[1], "quickshell", "wallpapers.json")
try:
    data = json.load(open(d))
    v = next(iter(data.values()))
    print(v.get("path", ""))
except: pass
PY
)
    if [[ -n "$_wp" && -f "$_wp" ]]; then
        bash "$VELUMERON_DIR/assets/scripts/wallpaper-set.sh" "$_wp" --no-showcase
    fi
    exit 0
fi

scheme="$2"
scheme_path="$FIXED_DIR/$scheme"
if [[ ! -f "$scheme_path" ]]; then
    echo "apply-theme: scheme not found: $scheme_path" >&2
    exit 1
fi

printf 'fixed:%s\n' "$scheme" > "$MODE_FILE"

# Generate the palette from the fixed scheme. `wallust cs` skips the configured [hooks], so run
# the post-processing steps ourselves (same as the old GUI). This themes the terminals / GTK /
# firefox from the raw ANSI scheme.
wallust --config-dir "$WALLUST_CFG" cs "$scheme_path"

# The shell reads quickshell/colors.json through SEMANTIC aliases (surfaces, borders, one accent);
# feeding it the raw ANSI scheme paints surfaces bright red/green/blue. Rebuild just that one file
# as quiet background shades + a signature accent. Terminals keep the untouched ANSI scheme.
qs_colors="$VELUMERON_USER_DIR/quickshell/colors.json"
mkdir -p "$(dirname "$qs_colors")"
python3 "$SCRIPT_DIR/lib/fixed-scheme-colors.py" "$scheme_path" "$qs_colors" 2>/dev/null || true

bash "$VELUMERON_DIR/assets/scripts/wallust/hyprland_lua-colors.sh" 2>/dev/null || true
hyprctl reload  >/dev/null 2>&1 || true
pywalfox update >/dev/null 2>&1 || true

# NO shell restart: quickshell watches colors.json (FileView in Colors.qml) and recolours in
# place, so the bar, the open settings menu and every panel stay put. Applying a fixed scheme is
# now seamless and live — exactly like an automatic wallpaper-driven colour change.
exit 0
