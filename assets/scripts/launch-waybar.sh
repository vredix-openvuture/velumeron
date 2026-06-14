#!/usr/bin/env bash
# Vutureland – Waybar Launcher
# Kills running Waybar instances and restarts with the current output configs.
# For rebuild + restart: ~/.setup/waybar.sh --rebuild

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"
OUTPUT_DIR="$VUTURELAND_USER_DIR/waybar-modular/output"
HOVER_FLAG="$VUTURELAND_USER_DIR/waybar-modular/.hover-hide"

# Alle per-Monitor config.json finden (output/{style}/{position}/{monitor}/config.json)
declare -a CONFIG_FILES=()
while IFS= read -r f; do CONFIG_FILES+=("$f"); done \
    < <(find "$OUTPUT_DIR" -mindepth 4 -maxdepth 5 -name "config.json" 2>/dev/null | sort)

if [[ ${#CONFIG_FILES[@]} -eq 0 ]]; then
    echo "No Waybar configs found in $OUTPUT_DIR"
    echo "Please run first: ~/.setup/waybar.sh"
    exit 1
fi

# Merge all configs into a single array. In hover-to-show mode the bars must not
# reserve an exclusive zone, otherwise every reveal/hide would reflow all windows.
MERGED_CONFIG="/tmp/waybar-merged-config.json"
if [[ -f "$HOVER_FLAG" ]]; then
    # Auto-hide mode: bar floats above windows, exclusive zone disabled so
    # windows fill the full screen while the bar is hidden.
    jq -s 'map(. + {"exclusive": false, "layer": "top"})' "${CONFIG_FILES[@]}" > "$MERGED_CONFIG"
else
    # Always-visible mode: standard waybar behaviour — layer "top" with the
    # default exclusive zone (bar height).  Explicitly delete any "exclusive"
    # key that may linger in the saved config so the default is restored.
    jq -s '[.[] | del(.exclusive) + {"layer": "top"}]' "${CONFIG_FILES[@]}" > "$MERGED_CONFIG"
fi

# Build merged style.css from all per-monitor style.css files
MERGED_STYLE="/tmp/waybar-merged-style.css"
{
    for cfg in "${CONFIG_FILES[@]}"; do
        local_style="$(dirname "$cfg")/style.css"
        if [[ -f "$local_style" ]]; then
            echo "@import url(\"${local_style}\");"
        fi
    done
} > "$MERGED_STYLE"

# Stop any previous hover daemon first — it would fight the fresh Waybar instance.
pkill -f "$SCRIPT_DIR/waybar-hover.sh" 2>/dev/null || true

# Kill and restart Waybar
if pgrep -x waybar &>/dev/null; then
    pkill -x waybar || true
    sleep 0.3
fi

waybar -c "$MERGED_CONFIG" -s "$MERGED_STYLE" > /tmp/waybar-launch.log 2>&1 &
disown

echo "Waybar started – ${#CONFIG_FILES[@]} bar(s) active"

# Hover-to-show: start the cursor daemon that hides the bar and reveals it on
# hovering the top screen edge.
if [[ -f "$HOVER_FLAG" ]]; then
    setsid bash "$SCRIPT_DIR/waybar-hover.sh" "$MERGED_CONFIG" > /tmp/waybar-hover.log 2>&1 &
    disown
    echo "Hover-to-show active"
fi
