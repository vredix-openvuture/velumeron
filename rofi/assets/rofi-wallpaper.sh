#!/usr/bin/env bash

wallpaper_dir=~/.config/vutureland/assets/wallpaper/horizontal
wallpaper_script=~/.config/vutureland/assets/scripts/wallpaper-set.sh
themes_file=~/.config/vutureland/assets/wallpaper/theme-names.txt
cache_dir=~/.cache/vutureland/wallpaper-thumbs

if [[ "$ROFI_RETV" == "0" || -z "$ROFI_RETV" ]]; then
    # Pre-generate thumbnails
    bash ~/.config/vutureland/rofi/assets/generate-thumbnail.sh

    while IFS= read -r f; do
        filename=$(basename "$f")
        stem="${filename%.*}"
        base="${stem%_hor}"
        thumb="$cache_dir/$stem.png"

        # Display name from themes.txt, fall back to base filename
        display="$base"
        if [[ -f "$themes_file" ]]; then
            while IFS= read -r line; do
                if [[ "$line" =~ ^${base}[[:space:]]*=[[:space:]]*\"(.+)\" ]]; then
                    display="${BASH_REMATCH[1]}"
                    break
                fi
            done < "$themes_file"
        fi

        # Icon = thumbnail if available, otherwise original
        icon="$f"
        [[ -f "$thumb" ]] && icon="$thumb"

        # info = original filename used in the else branch
        printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' "$display" "$icon" "$filename"
    done < <(find "$wallpaper_dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) | sort)
else
    # ROFI_INFO contains the original filename
    target="$wallpaper_dir/$ROFI_INFO"
    if [[ -f "$target" ]]; then
        bash "$wallpaper_script" "$target" >/dev/null 2>&1 &
        disown
    fi
fi
