#!/usr/bin/env bash
# Vutureland – Waybar Launcher
# Kills running Waybar instances and restarts with the current output configs.
# For rebuild + restart: ~/.setup/waybar.sh --rebuild

set -euo pipefail

VUTURELAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="$VUTURELAND_DIR/waybar-modular/output"

# Alle per-Monitor config.json finden (output/{style}/{position}/{monitor}/config.json)
declare -a CONFIG_FILES=()
while IFS= read -r f; do CONFIG_FILES+=("$f"); done \
    < <(find "$OUTPUT_DIR" -mindepth 4 -maxdepth 5 -name "config.json" 2>/dev/null | sort)

if [[ ${#CONFIG_FILES[@]} -eq 0 ]]; then
    echo "No Waybar configs found in $OUTPUT_DIR"
    echo "Please run first: ~/.setup/waybar.sh"
    exit 1
fi

# Merge all configs into a single array
MERGED_CONFIG="/tmp/waybar-merged-config.json"
jq -s '.' "${CONFIG_FILES[@]}" > "$MERGED_CONFIG"

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

# Kill and restart Waybar
if pgrep -x waybar &>/dev/null; then
    pkill -x waybar || true
    sleep 0.3
fi

waybar -c "$MERGED_CONFIG" -s "$MERGED_STYLE" > /tmp/waybar-launch.log 2>&1 &
disown

echo "Waybar started – ${#CONFIG_FILES[@]} bar(s) active"
