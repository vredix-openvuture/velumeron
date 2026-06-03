#!/usr/bin/env bash
# launch-swaync.sh — generate swaync config with monitor-relative dimensions, then launch
#
# Reads margin-top % and width % from the GUI settings file
# (defaults: 10% top margin, 23% width). Falls back to the values
# checked into config.json if anything goes wrong.

set -euo pipefail
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

SRC_CFG="$VUTURELAND_USER_DIR/swaync/config.json"
SRC_CSS="$VUTURELAND_USER_DIR/swaync/style.css"
GEN_CFG="/tmp/swaync-config-$USER.json"
GUI_SETTINGS="$VUTURELAND_USER_DIR/gui/settings.json"

# ── Read user preferences (with defaults) ─────────────────────────────────────
mt_pct=10
w_pct=23
if [[ -f "$GUI_SETTINGS" ]]; then
    mt_pct=$(jq -r '.swaync_margin_top_pct // 10' "$GUI_SETTINGS" 2>/dev/null || echo 10)
    w_pct=$(jq  -r '.swaync_width_pct      // 23' "$GUI_SETTINGS" 2>/dev/null || echo 23)
fi

# ── Primary (focused) monitor geometry ────────────────────────────────────────
read -r mon_w mon_h < <(hyprctl monitors -j 2>/dev/null \
    | jq -r '[.[] | select(.focused)] | .[0] | "\(.width) \(.height)"' \
    2>/dev/null || echo "1920 1080")

# Sanity fallbacks
[[ -z "$mon_w" || "$mon_w" == "null" ]] && mon_w=1920
[[ -z "$mon_h" || "$mon_h" == "null" ]] && mon_h=1080

margin_top=$(( mon_h * mt_pct / 100 ))
width=$(( mon_w * w_pct / 100 ))

# ── Generate the runtime config ──────────────────────────────────────────────
jq --argjson mt "$margin_top" --argjson w "$width" \
   '."control-center-margin-top" = $mt | ."control-center-width" = $w' \
   "$SRC_CFG" > "$GEN_CFG"

# ── Kill existing, launch ────────────────────────────────────────────────────
killall -q swaync 2>/dev/null || true
sleep 0.2
swaync -c "$GEN_CFG" -s "$SRC_CSS" &>/dev/null & disown

echo "swaync started — margin-top=${margin_top}px (${mt_pct}%) width=${width}px (${w_pct}%)"
