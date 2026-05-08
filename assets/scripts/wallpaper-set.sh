#!/usr/bin/env bash

chosen=""
showcase=true

# Parse arguments
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

if [[ "$showcase" == "true" ]]; then
    # Remember original workspaces and focused monitor
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
        hyprctl dispatch moveworkspacetomonitor "$tmp_ws $mon"
        hyprctl dispatch focusmonitor "$mon"
        hyprctl dispatch workspace "$tmp_ws"
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
wallust --config-dir ~/.config/vutureland/wallust run "$chosen" -q

if [[ "$showcase" == "true" ]]; then
    # Wait for awww transition to finish
    sleep 2

    ~/.config/vutureland/assets/scripts/launch-waybar.sh

    # Restore original workspaces
    i=0
    for mon in "${monitors[@]}"; do
        hyprctl dispatch focusmonitor "$mon"
        hyprctl dispatch workspace "${original_workspaces[$i]}"
        i=$((i + 1))
    done

    i=$(( ${#monitors[@]} - 1 ))
    while (( i >= 0 )); do
        hyprctl dispatch focusmonitor "${monitors[$i]}"
        hyprctl dispatch workspace "${original_workspaces[$i]}"
        i=$((i - 1))
    done

    hyprctl dispatch focusmonitor "$focused_monitor"
fi
