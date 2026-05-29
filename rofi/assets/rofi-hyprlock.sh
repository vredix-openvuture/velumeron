#!/usr/bin/env bash
# Rofi custom mode: pick a hyprlock theme
# Lists .conf files from hyprlock-themes/, shows preview, applies monitor substitution
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)/assets/scripts/lib/env.sh"

THEMES_DIR="$VUTURELAND_DIR/hypr.lua/hyprlock-themes"
ACTIVE_CONF="$VUTURELAND_USER_DIR/hypr.lua/hyprlock.conf"
BLACK_WP="$VUTURELAND_DIR/assets/wallpaper/pure-black.jpg"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/vutureland/hyprlock-thumbs"
THUMB_W=400
THUMB_H=240

mkdir -p "$CACHE_DIR"

# ──────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────

_primary_monitor() {
    hyprctl monitors -j | jq -r '[.[] | select(.focused)] | .[0].name'
}

_other_monitors() {
    hyprctl monitors -j | jq -r '[.[] | select(.focused | not)] | .[].name'
}

# Extract the 'path' value from the FIRST background block in a theme file
_bg_path() {
    awk '
        /^background[[:space:]]*\{/ { in_block=1; found=0; next }
        in_block && /path[[:space:]]*=/ {
            match($0, /path[[:space:]]*=[[:space:]]*(.+)/, a)
            print a[1]
            exit
        }
        in_block && /^\}/ { in_block=0 }
    ' "$1" | sed 's/^[[:space:]]*//' | sed "s|~|$HOME|g"
}

# Generate a thumbnail for a theme; outputs path to thumb PNG
_ensure_thumb() {
    local theme_file="$1"
    local name="$2"
    local thumb="$CACHE_DIR/${name}.png"
    local force="${3:-}"   # pass "force" to regenerate

    if [[ -f "$thumb" && -z "$force" && ! "$theme_file" -nt "$thumb" ]]; then
        echo "$thumb"
        return
    fi

    local bg
    bg=$(_bg_path "$theme_file")

    if [[ "$bg" == "screenshot" ]]; then
        # Live blurred screenshot as preview
        local tmp_screen
        tmp_screen=$(mktemp /tmp/hyprlock-preview-XXXXXX.png)
        grim "$tmp_screen" 2>/dev/null || \
            magick "$BLACK_WP" "$tmp_screen" 2>/dev/null
        magick "$tmp_screen" \
            -resize "${THUMB_W}x${THUMB_H}^" \
            -gravity Center -extent "${THUMB_W}x${THUMB_H}" \
            -blur 0x16 \
            PNG32:"$thumb" 2>/dev/null
        rm -f "$tmp_screen"
    elif [[ -f "$bg" ]]; then
        magick "$bg" \
            -resize "${THUMB_W}x${THUMB_H}^" \
            -gravity Center -extent "${THUMB_W}x${THUMB_H}" \
            PNG32:"$thumb" 2>/dev/null
    else
        magick "$BLACK_WP" \
            -resize "${THUMB_W}x${THUMB_H}^" \
            -gravity Center -extent "${THUMB_W}x${THUMB_H}" \
            PNG32:"$thumb" 2>/dev/null
    fi

    echo "$thumb"
}

# Apply monitor substitutions and write active-hyprlock.conf
_apply_theme() {
    local theme_file="$1"
    local primary other_mons=()
    primary=$(_primary_monitor)
    readarray -t other_mons < <(_other_monitors)

    local content
    content=$(cat "$theme_file")

    # Substitute {{mon1}} with primary monitor
    content="${content//\{\{mon1\}\}/$primary}"

    # Substitute {{monN}} for each secondary monitor
    local i n mon
    for i in "${!other_mons[@]}"; do
        n=$((i + 2))
        mon="${other_mons[$i]}"
        if [[ "$content" == *"{{mon${n}}}"* ]]; then
            content="${content//\{\{mon${n}\}\}/$mon}"
        else
            # No placeholder for this monitor → append a black background block
            content+=$'\n'"background {"$'\n'"    monitor = $mon"$'\n'"    path = $BLACK_WP"$'\n'"}"
        fi
    done

    printf '%s\n' "$content" > "${ACTIVE_CONF/#\~/$HOME}"
}

# ──────────────────────────────────────────────────────────────
# Rofi protocol
# ──────────────────────────────────────────────────────────────

if [[ "$ROFI_RETV" == "0" || -z "$ROFI_RETV" ]]; then
    # List mode: output one entry per theme file
    while IFS= read -r f; do
        name=$(basename "$f" .conf)
        thumb=$(_ensure_thumb "$f" "$name")
        [[ -f "$thumb" ]] || thumb="$BLACK_WP"
        printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' "$name" "$thumb" "$(basename "$f")"
    done < <(find "$THEMES_DIR" -maxdepth 1 -name "*.conf" | sort)
else
    # Selection made: ROFI_INFO contains the .conf filename
    theme_file="$THEMES_DIR/$ROFI_INFO"
    if [[ -f "$theme_file" ]]; then
        _apply_theme "$theme_file"
    fi
fi
