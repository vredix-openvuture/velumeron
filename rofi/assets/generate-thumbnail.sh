#!/usr/bin/env bash

wallpaper_dir=~/.config/vutureland/assets/wallpaper/horizontal
cache_dir=~/.cache/vutureland/wallpaper-thumbs
thumb_size=400
radius=10

mkdir -p "$cache_dir"

_make_thumb() {
    local src="$1" thumb="$2"
    magick "$src" -resize "${thumb_size}x" \
        \( +clone -threshold -1 -fill black -colorize 100% \
           -fill white -draw "roundrectangle 0,0 %[fx:w-1],%[fx:h-1] ${radius},${radius}" \) \
        -alpha off -compose CopyOpacity -composite \
        PNG32:"$thumb"
}

while IFS= read -r f; do
    name=$(basename "$f")
    stem="${name%.*}"
    ext="${name##*.}"
    thumb="$cache_dir/$stem.png"

    [[ -f "$thumb" && ! "$f" -nt "$thumb" ]] && continue

    case "${ext,,}" in
        mp4|webm|mkv|avi|mov)
            tmp_frame=$(mktemp /tmp/thumb-frame-XXXXXX.jpg)
            ffmpeg -y -i "$f" -vframes 1 -q:v 2 "$tmp_frame" &>/dev/null && \
                _make_thumb "$tmp_frame" "$thumb"
            rm -f "$tmp_frame"
            ;;
        *)
            _make_thumb "$f" "$thumb"
            ;;
    esac
done < <(find "$wallpaper_dir" -maxdepth 1 -type f \( \
    -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \
    -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \) | sort)
