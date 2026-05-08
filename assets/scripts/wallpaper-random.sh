#!/usr/bin/env bash

wallpaper_dir=~/.config/vutureland/assets/wallpaper/horizontal
wallpaper_script=~/.config/vutureland/assets/scripts/wallpaper-set.sh
interval_minutes=10

while true; do
    mapfile -t files < <(find "$wallpaper_dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \))

    if [[ ${#files[@]} -gt 0 ]]; then
        pick="${files[RANDOM % ${#files[@]}]}"
        bash "$wallpaper_script" --no-showcase "$pick"
    fi

    remaining=$interval_minutes
    while (( remaining > 0 )); do
        echo "Next change in $remaining minutes"
        sleep 60
        remaining=$((remaining - 1))
    done
done
