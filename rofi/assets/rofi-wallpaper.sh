#!/usr/bin/env bash
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)/assets/scripts/lib/env.sh"

wallpaper_dir="$WALLPAPER_DIR_H"
wallpaper_script="$VELUMERON_DIR/assets/scripts/wallpaper-set.sh"
themes_file="$VELUMERON_DIR/assets/wallpaper/theme-names.txt"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/velumeron/wallpaper-thumbs"
sets_json="$VELUMERON_USER_DIR/assets/sets.json"
gui_settings="$VELUMERON_USER_DIR/gui/settings.json"

# Source toggle (GUI → Settings → "Rofi shows"). Only use sets when the setting
# asks for it AND at least one set exists; otherwise list the wallpapers.
rofi_source="wallpaper"
if [[ -f "$gui_settings" ]] && command -v jq >/dev/null 2>&1; then
    rofi_source=$(jq -r '.rofi_source // "wallpaper"' "$gui_settings" 2>/dev/null || echo wallpaper)
fi
use_sets=0
if [[ "$rofi_source" == "sets" && -f "$sets_json" ]]; then
    [[ "$(jq 'length' "$sets_json" 2>/dev/null || echo 0)" -gt 0 ]] && use_sets=1
fi

if [[ "$ROFI_RETV" == "0" || -z "$ROFI_RETV" ]]; then
    bash "$VELUMERON_DIR/rofi/assets/generate-thumbnail.sh"

    if [[ "$use_sets" == 1 ]]; then
        # List sets (name + a preview of the set's first image)
        while IFS= read -r sid; do
            [[ -z "$sid" ]] && continue
            name=$(jq -r --arg s "$sid" '.[$s].name // $s' "$sets_json")
            first=$(jq -r --arg s "$sid" '.[$s].images[0].file // empty' "$sets_json")
            icon="$cache_dir/${first%.*}.png"
            [[ -f "$icon" ]] || icon=""
            printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' "$name" "$icon" "set:$sid"
        done < <(jq -r 'keys[]' "$sets_json")
    else
        # List wallpapers from the (possibly custom) horizontal folder
        while IFS= read -r f; do
            filename=$(basename "$f")
            stem="${filename%.*}"
            base="${stem%_hor}"; base="${base%_vid}"
            id="${base#wp_}"
            thumb="$cache_dir/$stem.png"

            display="$base"
            if [[ -f "$themes_file" ]]; then
                while IFS= read -r line; do
                    if [[ "$line" =~ ^${id}[[:space:]]*=[[:space:]]*\"(.+)\" || \
                          "$line" =~ ^${base}[[:space:]]*=[[:space:]]*\"(.+)\" ]]; then
                        display="${BASH_REMATCH[1]}"; break
                    fi
                done < "$themes_file"
            fi
            icon="$f"; [[ -f "$thumb" ]] && icon="$thumb"
            printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' "$display" "$icon" "$filename"
        done < <(find "$wallpaper_dir" -maxdepth 1 -type f \( \
            -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \
            -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \) | sort)
    fi
else
    if [[ "$ROFI_INFO" == set:* ]]; then
        bash "$wallpaper_script" --set "${ROFI_INFO#set:}" > /tmp/wallpaper-set.log 2>&1 &
        disown
    else
        target="$wallpaper_dir/$ROFI_INFO"
        if [[ -f "$target" ]]; then
            set_id=""
            if [[ -f "$sets_json" ]]; then
                set_id=$(jq -r --arg f "$ROFI_INFO" \
                    'to_entries[] | select(.value.images[]?.file == $f) | .key' \
                    "$sets_json" 2>/dev/null | head -1)
            fi
            if [[ -n "$set_id" ]]; then
                bash "$wallpaper_script" --set "$set_id" > /tmp/wallpaper-set.log 2>&1 &
            else
                bash "$wallpaper_script" --hor "$target" > /tmp/wallpaper-set.log 2>&1 &
            fi
            disown
        fi
    fi
fi
