#!/usr/bin/env bash
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)/assets/scripts/lib/env.sh"

wallpaper_dir="$WALLPAPER_DIR_H"
wallpaper_script="$VUTURELAND_DIR/assets/scripts/wallpaper-set.sh"
themes_file="$VUTURELAND_DIR/assets/wallpaper/theme-names.txt"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/vutureland/wallpaper-thumbs"

if [[ "$ROFI_RETV" == "0" || -z "$ROFI_RETV" ]]; then
    # Pre-generate thumbnails (images + videos)
    bash "$VUTURELAND_DIR/rofi/assets/generate-thumbnail.sh"

    while IFS= read -r f; do
        filename=$(basename "$f")
        stem="${filename%.*}"
        base="${stem%_hor}"
        base="${base%_vid}"
        # Strip wp_ prefix for theme name lookup
        id="${base#wp_}"
        thumb="$cache_dir/$stem.png"

        # Display name from themes.txt, fall back to base filename
        display="$base"
        if [[ -f "$themes_file" ]]; then
            while IFS= read -r line; do
                if [[ "$line" =~ ^${id}[[:space:]]*=[[:space:]]*\"(.+)\" || \
                      "$line" =~ ^${base}[[:space:]]*=[[:space:]]*\"(.+)\" ]]; then
                    display="${BASH_REMATCH[1]}"
                    break
                fi
            done < "$themes_file"
        fi

        icon="$f"
        [[ -f "$thumb" ]] && icon="$thumb"

        printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' "$display" "$icon" "$filename"
    done < <(find "$wallpaper_dir" -maxdepth 1 -type f \( \
        -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \
        -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \) | sort)
else
    # ROFI_INFO contains the original filename
    target="$wallpaper_dir/$ROFI_INFO"
    if [[ -f "$target" ]]; then
        sets_json="$VUTURELAND_USER_DIR/assets/sets.json"
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
