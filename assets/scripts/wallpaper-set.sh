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
base="${filename%.*}"
base="${base%_hor}"

# In Hyprland Lua mode, dispatch args are evaluated as Lua inside hl.dispatch().
# Use hl.dsp.focus() — the same API as in keybinds.lua.
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

    # Switch to temporary showcase workspaces
    i=0
    for mon in "${monitors[@]}"; do
        tmp_ws=$((111 + i))
        focusmon "$mon"
        focusws "$tmp_ws"
        i=$((i + 1))
    done
fi

killall waybar

# Set wallpaper on each monitor
while IFS=';' read -r name transform width height; do
    if [[ "$transform" == "1" || "$transform" == "3" ]] || (( height > width )); then
        match=$(find "$wallpaper_dir/vertical" -name "$base*" | head -1)
    else
        match="$chosen"
    fi

    if [[ -n "$match" && -f "$match" ]]; then
        awww img -o "$name" --transition-type wipe --transition-angle 120 --transition-step 200 --transition-fps 200 --transition-duration 2 "$match"
    else
        awww img -o "$name" "$chosen"
    fi
done < <(hyprctl monitors -j | jq -r '.[] | "\(.name);\(.transform);\(.width);\(.height)"')

# Generate new color scheme from wallpaper
wallust --config-dir ~/.config/vutureland/wallust run "$chosen"

if [[ "$showcase" == "true" ]]; then
    sleep 2
    ~/.config/vutureland/assets/scripts/launch-waybar.sh

    # Restore original workspaces
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
