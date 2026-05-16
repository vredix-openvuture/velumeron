#!/usr/bin/env bash
# wallpaper-set.sh [--no-showcase] [--hor FILE] [--ver FILE]
# Legacy: wallpaper-set.sh [--no-showcase] FILE  (auto-detects, finds counterpart)

showcase=true
hor_file=""
ver_file=""
WP_H=~/.config/vutureland/assets/wallpaper/horizontal
WP_V=~/.config/vutureland/assets/wallpaper/vertical

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-showcase) showcase=false; shift ;;
        --hor)         hor_file="$2"; shift 2 ;;
        --ver)         ver_file="$2"; shift 2 ;;
        *)
            file="$1"; shift
            stem=$(basename "${file%.*}")
            if [[ "$stem" == *"_ver" ]]; then
                ver_file="$file"
                # Look for horizontal counterpart
                id=$(echo "$stem" | sed -E 's/^wp_([a-zA-Z0-9]{6})_ver$/\1/')
                match=$(find "$WP_H" -maxdepth 1 -name "wp_${id}_hor*" \
                                                 -o -name "wp_${id}_vid_hor*" 2>/dev/null | head -1)
                [[ -n "$match" ]] && hor_file="$match"
            else
                hor_file="$file"
                # Look for vertical counterpart
                id=$(echo "$stem" | sed -E 's/^wp_([a-zA-Z0-9]{6})_(vid_hor|hor)$/\1/')
                match=$(find "$WP_V" -maxdepth 1 -name "wp_${id}_ver*" 2>/dev/null | head -1)
                [[ -n "$match" ]] && ver_file="$match"
            fi
            ;;
    esac
done

if [[ -z "$hor_file" && -z "$ver_file" ]]; then
    echo "Usage: wallpaper-set.sh [--no-showcase] [--hor FILE] [--ver FILE]"
    exit 1
fi

focusmon() { hyprctl dispatch "hl.dsp.focus({monitor=\"${1}\"})"; }
focusws()  { hyprctl dispatch "hl.dsp.focus({workspace=${1}})"; }

if [[ "$showcase" == "true" ]]; then
    focused_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name')
    mapfile -t monitors < <(hyprctl monitors -j | jq -r '.[].name')
    original_workspaces=()
    for mon in "${monitors[@]}"; do
        ws=$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | .activeWorkspace.id')
        original_workspaces+=("$ws")
    done
    i=0
    for mon in "${monitors[@]}"; do
        focusmon "$mon"; focusws "$((111 + i))"; i=$((i + 1))
    done
fi

killall waybar

# Determine if horizontal file is video
hor_is_video=false
if [[ -n "$hor_file" ]]; then
    ext="${hor_file##*.}"
    case "${ext,,}" in mp4|webm|mkv|avi|mov) hor_is_video=true ;; esac
    pkill -f mpvpaper 2>/dev/null || true
    "$hor_is_video" || sleep 0.1
fi

while IFS=';' read -r name transform width height; do
    is_vertical=false
    if [[ "$transform" == "1" || "$transform" == "3" ]] || (( height > width )); then
        is_vertical=true
    fi

    if "$is_vertical"; then
        [[ -z "$ver_file" ]] && continue
        awww img -o "$name" "$ver_file"
    else
        [[ -z "$hor_file" ]] && continue
        if "$hor_is_video"; then
            mpvpaper -o "no-audio loop" "$name" "$hor_file" & disown
        else
            awww img -o "$name" --transition-type wipe --transition-angle 120 \
                --transition-step 200 --transition-fps 200 --transition-duration 2 "$hor_file"
        fi
    fi
done < <(hyprctl monitors -j | jq -r '.[] | "\(.name);\(.transform);\(.width);\(.height)"')

# Wallust: prefer horizontal source; extract frame for videos
wallust_src="${hor_file:-$ver_file}"
ext="${wallust_src##*.}"
case "${ext,,}" in
    mp4|webm|mkv|avi|mov)
        tmp=$(mktemp /tmp/wp-frame-XXXXXX.jpg)
        ffmpeg -y -i "$wallust_src" -vframes 1 -q:v 2 "$tmp" &>/dev/null
        wallust --config-dir ~/.config/vutureland/wallust run "$tmp"
        rm -f "$tmp"
        ;;
    *)
        wallust --config-dir ~/.config/vutureland/wallust run "$wallust_src"
        ;;
esac

if [[ "$showcase" == "true" ]]; then
    sleep 2
    ~/.config/vutureland/assets/scripts/launch-waybar.sh
    i=0
    for mon in "${monitors[@]}"; do
        focusmon "$mon"; focusws "${original_workspaces[$i]}"; i=$((i + 1))
    done
    i=$(( ${#monitors[@]} - 1 ))
    while (( i >= 0 )); do
        focusmon "${monitors[$i]}"; focusws "${original_workspaces[$i]}"; i=$((i - 1))
    done
    focusmon "$focused_monitor"
fi
