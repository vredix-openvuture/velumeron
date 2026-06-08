#!/usr/bin/env bash
# launch-swaync.sh — write swaync config with monitor-relative dimensions
# into ~/.config/swaync/config.json (the path swaync looks at by default,
# regardless of who started it — systemd user unit, D-Bus activation, or
# us calling it directly). style.css is written there by sync_templates
# (a real file with the palette @import rewritten to an absolute path).

set -euo pipefail
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

SRC_CFG="$VUTURELAND_USER_DIR/swaync/config.json"
DST_CFG="$HOME/.config/swaync/config.json"
DST_STYLE="$HOME/.config/swaync/style.css"
SW_COLORS="$VUTURELAND_USER_DIR/assets/colors_gtk.css"

# Active app theme (set by the waybar design picker). The matching swaync theme
# is swaync/themes/<active>.css; fall back to the legacy style.css if absent.
# Read defensively: a missing active-theme file must not abort under `set -e`.
SW_THEME="miboro"
if [[ -f "$VUTURELAND_USER_DIR/active-theme" ]]; then
    SW_THEME="$(tr -d '[:space:]' < "$VUTURELAND_USER_DIR/active-theme")"
    [[ -z "$SW_THEME" ]] && SW_THEME="miboro"
fi
SRC_STYLE="$VUTURELAND_USER_DIR/swaync/themes/$SW_THEME.css"
[[ -f "$SRC_STYLE" ]] || SRC_STYLE="$VUTURELAND_USER_DIR/swaync/themes/miboro.css"
[[ -f "$SRC_STYLE" ]] || SRC_STYLE="$VUTURELAND_USER_DIR/swaync/style.css"
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

# ── Write style.css to the default path too ──────────────────────────────────
# swaync started by its systemd unit / D-Bus runs `swaync` with no -s, so it
# reads ~/.config/swaync/style.css. GTK4 resolves the template's relative
# `@import url("../assets/colors_gtk.css")` against the file's own directory, so
# rewrite it to an absolute path. Done on every launch (not just sync) so a
# stale or foreign style.css from an older install / another theme gets
# overwritten with ours on the next login without needing a full re-sync.
if [[ -f "$SRC_STYLE" ]]; then
    [[ -L "$DST_STYLE" ]] && rm -f "$DST_STYLE"
    sed "s#\.\./assets/colors_gtk\.css#${SW_COLORS}#" "$SRC_STYLE" > "$DST_STYLE"
fi

# ── Restart swaync: prefer systemd unit (it's usually the one running) ───────
if systemctl --user is-active swaync.service >/dev/null 2>&1; then
    systemctl --user restart swaync.service
else
    killall -q swaync 2>/dev/null || true
    sleep 0.2
    swaync &>/dev/null & disown
fi

echo "swaync restarted — margin-top=${margin_top}px (${mt_pct}%) width=${width}px (${w_pct}%)"
