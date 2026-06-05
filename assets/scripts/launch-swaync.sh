#!/usr/bin/env bash
# launch-swaync.sh — write swaync config with monitor-relative dimensions
# into ~/.config/swaync/config.json (the path swaync looks at by default,
# regardless of who started it — systemd user unit, D-Bus activation, or
# us calling it directly). style.css is already a symlink there (created
# by sync_templates).

set -euo pipefail
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

SRC_CFG="$VUTURELAND_USER_DIR/swaync/config.json"
DST_CFG="$HOME/.config/swaync/config.json"
GUI_SETTINGS="$VUTURELAND_USER_DIR/gui/settings.json"

# ── Read user preferences (with defaults) ────────────────────────────────────
mt_pct=10
w_pct=23
if [[ -f "$GUI_SETTINGS" ]]; then
    mt_pct=$(jq -r '.swaync_margin_top_pct // 10' "$GUI_SETTINGS" 2>/dev/null || echo 10)
    w_pct=$(jq  -r '.swaync_width_pct      // 23' "$GUI_SETTINGS" 2>/dev/null || echo 23)
fi

# ── Primary (focused) monitor geometry ───────────────────────────────────────
read -r mon_w mon_h < <(hyprctl monitors -j 2>/dev/null \
    | jq -r '[.[] | select(.focused)] | .[0] | "\(.width) \(.height)"' \
    2>/dev/null || echo "1920 1080")
[[ -z "$mon_w" || "$mon_w" == "null" ]] && mon_w=1920
[[ -z "$mon_h" || "$mon_h" == "null" ]] && mon_h=1080

margin_top=$(( mon_h * mt_pct / 100 ))
width=$(( mon_w * w_pct / 100 ))

# ── Write config to the path swaync reads by default ─────────────────────────
mkdir -p "$(dirname "$DST_CFG")"
jq --argjson mt "$margin_top" --argjson w "$width" \
   '."control-center-margin-top" = $mt | ."control-center-width" = $w' \
   "$SRC_CFG" > "$DST_CFG"

# ── Restart swaync: prefer systemd unit (it's usually the one running) ───────
if systemctl --user is-active swaync.service >/dev/null 2>&1; then
    systemctl --user restart swaync.service
else
    killall -q swaync 2>/dev/null || true
    sleep 0.2
    swaync &>/dev/null & disown
fi

echo "swaync restarted — margin-top=${margin_top}px (${mt_pct}%) width=${width}px (${w_pct}%)"
