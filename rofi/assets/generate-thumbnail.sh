#!/usr/bin/env bash
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)/assets/scripts/lib/env.sh"

WALLPAPER_H="$WALLPAPER_DIR_H"
WALLPAPER_V="$WALLPAPER_DIR_V"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/velumeron/wallpaper-thumbs"
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

_process_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return

    while IFS= read -r f; do
        local name stem ext thumb
        name=$(basename "$f")
        stem="${name%.*}"
        ext="${name##*.}"
        thumb="$cache_dir/$stem.png"

        [[ -f "$thumb" && ! "$f" -nt "$thumb" ]] && continue

        case "${ext,,}" in
            mp4|webm|mkv|avi|mov)
                local tmp
                tmp=$(mktemp /tmp/thumb-frame-XXXXXX.jpg)
                ffmpeg -y -i "$f" -vframes 1 -q:v 2 "$tmp" &>/dev/null && \
                    _make_thumb "$tmp" "$thumb"
                rm -f "$tmp"
                ;;
            *)
                _make_thumb "$f" "$thumb"
                ;;
        esac
    done < <(find "$dir" -maxdepth 1 -type f \( \
        -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \
        -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \) | sort)
}

_process_dir "$WALLPAPER_H"
_process_dir "$WALLPAPER_V"
