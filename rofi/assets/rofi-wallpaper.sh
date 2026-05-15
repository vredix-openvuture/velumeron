#!/usr/bin/env bash

wallpaper_dir=~/.config/vutureland/assets/wallpaper/horizontal
wallpaper_script=~/.config/vutureland/assets/scripts/wallpaper-set.sh
themes_file=~/.config/vutureland/assets/wallpaper/theme-names.txt
cache_dir=~/.cache/vutureland/wallpaper-thumbs

if [[ "$ROFI_RETV" == "0" || -z "$ROFI_RETV" ]]; then
    # Pre-generate thumbnails (images + videos)
    bash ~/.config/vutureland/rofi/assets/generate-thumbnail.sh

    while IFS= read -r f; do
        filename=$(basename "$f")
        stem="${filename%.*}"
        base="${stem%_hor}"
        # Strip wp_/vwp_ prefix for theme name lookup
        id="${base#vwp_}"
        id="${id#wp_}"
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
        bash "$wallpaper_script" "$target" > /tmp/wallpaper-set.log 2>&1 &
        disown
    fi
fi
