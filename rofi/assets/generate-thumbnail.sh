#!/usr/bin/env bash

wallpaper_dir=~/.config/vutureland/assets/wallpaper/horizontal
cache_dir=~/.cache/vutureland/wallpaper-thumbs
thumb_size=400
radius=10

mkdir -p "$cache_dir"

while IFS= read -r f; do
    name=$(basename "$f")
    stem="${name%.*}"
    thumb="$cache_dir/$stem.png"

    if [[ ! -f "$thumb" || "$f" -nt "$thumb" ]]; then
        magick "$f" -resize "${thumb_size}x" \
            \( +clone -threshold -1 -fill black -colorize 100% \
               -fill white -draw "roundrectangle 0,0 %[fx:w-1],%[fx:h-1] ${radius},${radius}" \) \
            -alpha off -compose CopyOpacity -composite \
            PNG32:"$thumb"
    fi
done < <(find "$wallpaper_dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \))
