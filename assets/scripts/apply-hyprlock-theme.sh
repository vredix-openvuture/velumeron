#!/usr/bin/env bash
# Write the active hyprlock.conf from a theme, substituting THIS machine's
# monitors into the {{mon1}}, {{mon2}}, … placeholders. Shared by rofi-hyprlock.sh
# (theme picker), launch-hyprlock.sh (self-heal before locking) and setup.
#
# Usage: apply-hyprlock-theme.sh [theme-name]
#   No argument → reuse the remembered theme, falling back to a sane default.
set -euo pipefail
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

THEMES_DIR="$VUTURELAND_DIR/hypr.lua/hyprlock-themes"
ACTIVE_CONF="$VUTURELAND_USER_DIR/hypr.lua/hyprlock.conf"
MARKER="$VUTURELAND_USER_DIR/hypr.lua/.hyprlock-theme"
BLACK_WP="$VUTURELAND_DIR/assets/wallpaper/hyprlock/pure-black.jpg"
DEFAULT_THEME="glitch"

# ── Resolve which theme to apply ─────────────────────────────────────────────
theme="${1:-}"
[[ -z "$theme" && -f "$MARKER" ]] && theme=$(cat "$MARKER" 2>/dev/null || true)
[[ -z "$theme" ]] && theme="$DEFAULT_THEME"
theme_file="$THEMES_DIR/$theme.conf"
# Fall back to any available theme if the remembered one is gone.
if [[ ! -f "$theme_file" ]]; then
    theme_file=$(find "$THEMES_DIR" -maxdepth 1 -name '*.conf' | sort | head -1 || true)
    [[ -n "$theme_file" ]] && theme=$(basename "$theme_file" .conf)
fi
[[ -f "$theme_file" ]] || exit 0

# ── Current monitors ─────────────────────────────────────────────────────────
primary=$(hyprctl monitors -j 2>/dev/null | jq -r '[.[] | select(.focused)] | .[0].name')
[[ -z "$primary" || "$primary" == "null" ]] && \
    primary=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name')
[[ -z "$primary" || "$primary" == "null" ]] && exit 0
readarray -t others < <(hyprctl monitors -j 2>/dev/null \
    | jq -r --arg p "$primary" '[.[] | select(.name != $p)] | .[].name')

# ── Substitute placeholders ──────────────────────────────────────────────────
content=$(cat "$theme_file")
content="${content//\{\{mon1\}\}/$primary}"
for i in "${!others[@]}"; do
    n=$((i + 2)); mon="${others[$i]}"
    if [[ "$content" == *"{{mon${n}}}"* ]]; then
        content="${content//\{\{mon${n}\}\}/$mon}"
    else
        content+=$'\n'"background {"$'\n'"    monitor = $mon"$'\n'"    path = $BLACK_WP"$'\n'"}"
    fi
done

# hyprlock (older versions, incl. 0.9.x) does NOT expand ~ in background:path,
# so make the image paths absolute and point them at the real (package) asset
# dir — this also removes the dependency on the per-user assets symlink. Then
# drop any leftover background block whose {{monN}} was never substituted
# (the theme expects more monitors than this machine has).
content=$(printf '%s\n' "$content" \
    | sed -e "s#~/.config/vutureland/assets/#${VUTURELAND_DIR}/assets/#g" \
          -e "s#~/#${HOME}/#g" \
    | awk '
        /^background[[:space:]]*\{/ { buf=$0; c=1; ph=0; next }
        c { buf=buf ORS $0
            if ($0 ~ /\{\{mon[0-9]+\}\}/) ph=1
            if ($0 ~ /^\}/) { c=0; if (!ph) print buf }
            next }
        { print }
    ')

mkdir -p "$(dirname "$ACTIVE_CONF")"
printf '%s\n' "$content" > "$ACTIVE_CONF"
printf '%s\n' "$theme" > "$MARKER"
