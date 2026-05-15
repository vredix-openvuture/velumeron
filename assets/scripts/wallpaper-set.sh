#!/usr/bin/env bash

chosen=""
showcase=true

for arg in "$@"; do
    if [[ "$arg" == "--no-showcase" ]]; then
        showcase=false
    else
        chosen="$arg"
    fi
done

if [[ -z "$chosen" ]]; then
    echo "Usage: wallpaper-set.sh [--no-showcase] <wallpaper-path>"
    exit 1
fi

wallpaper_dir=~/.config/vutureland/assets/wallpaper
filename=$(basename "$chosen")
ext="${filename##*.}"
stem="${filename%.*}"
base="${stem%_hor}"
base="${base%_ver}"
base="${base%_vid}"
# Strip wp_ prefix to get the shared ID for matching vertical/video counterparts
id="${base#wp_}"

is_video=false
case "${ext,,}" in
    mp4|webm|mkv|avi|mov) is_video=true ;;
esac

# In Hyprland Lua mode, dispatch args are evaluated as Lua inside hl.dispatch().
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
        tmp_ws=$((111 + i))
        focusmon "$mon"
        focusws "$tmp_ws"
        i=$((i + 1))
    done
fi

killall waybar

if "$is_video"; then
    # Kill any running mpvpaper instances before starting fresh ones
    pkill -f mpvpaper 2>/dev/null || true
    sleep 0.2

    while IFS=';' read -r name transform width height; do
        if [[ "$transform" == "1" || "$transform" == "3" ]] || (( height > width )); then
            # Vertical monitor: use matching static wp (wp_ID_ver.*), not vwp
            match=$(find "$wallpaper_dir/vertical" -maxdepth 1 -name "wp_${id}*" | head -1)
            if [[ -n "$match" && -f "$match" ]]; then
                awww img -o "$name" "$match"
            fi
        else
            # Horizontal monitor: video via mpvpaper
            mpvpaper -o "no-audio loop" "$name" "$chosen" &
            disown
        fi
    done < <(hyprctl monitors -j | jq -r '.[] | "\(.name);\(.transform);\(.width);\(.height)"')

    # Extract a single frame for wallust color generation
    tmp_frame=$(mktemp /tmp/wallpaper-frame-XXXXXX.jpg)
    ffmpeg -y -i "$chosen" -vframes 1 -q:v 2 "$tmp_frame" &>/dev/null
    wallust --config-dir ~/.config/vutureland/wallust run "$tmp_frame"
    rm -f "$tmp_frame"

else
    # Static image: kill mpvpaper, use awww for all monitors
    pkill -f mpvpaper 2>/dev/null || true
    sleep 0.2

    while IFS=';' read -r name transform width height; do
        if [[ "$transform" == "1" || "$transform" == "3" ]] || (( height > width )); then
            match=$(find "$wallpaper_dir/vertical" -maxdepth 1 -name "${base}*" | head -1)
        else
            match="$chosen"
        fi

        if [[ -n "$match" && -f "$match" ]]; then
            awww img -o "$name" --transition-type wipe --transition-angle 120 --transition-step 200 --transition-fps 200 --transition-duration 2 "$match"
        else
            awww img -o "$name" "$chosen"
        fi
    done < <(hyprctl monitors -j | jq -r '.[] | "\(.name);\(.transform);\(.width);\(.height)"')

    wallust --config-dir ~/.config/vutureland/wallust run "$chosen"
fi

if [[ "$showcase" == "true" ]]; then
    sleep 2
    ~/.config/vutureland/assets/scripts/launch-waybar.sh

    i=0
    for mon in "${monitors[@]}"; do
        focusmon "$mon"
        focusws "${original_workspaces[$i]}"
        i=$((i + 1))
    done

    i=$(( ${#monitors[@]} - 1 ))
    while (( i >= 0 )); do
        focusmon "${monitors[$i]}"
        focusws "${original_workspaces[$i]}"
        i=$((i - 1))
    done

    focusmon "$focused_monitor"
fi
