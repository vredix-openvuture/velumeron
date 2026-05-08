#!/usr/bin/env bash

path=~/.config/vutureland

launch_wlogout="wlogout -l $path/wlogout/layout -C $path/wlogout/style.css"
launch_waybar="waybar   -c $path/waybar/config.json -s $path/waybar/style.css"
launch_swaync="swaync   -c $path/swaync/config.json -s $path/swaync/style.css"

# === Define flags ===
flag_wlogout=false
flag_waybar=false
flag_swaync=false

# === Parse arguments ===
for arg in "$@"; do
    case "$arg" in
        --wlogout) flag_wlogout=true ;;
        --waybar)  flag_waybar=true  ;;
        --swaync)  flag_swaync=true  ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# === Actions ===
did_something=false

if [[ "$flag_wlogout" == "true" ]]; then
    $launch_wlogout
    did_something=true
fi

if [[ "$flag_waybar" == "true" ]]; then
    $launch_waybar
    did_something=true
fi

if [[ "$flag_swaync" == "true" ]]; then
    $launch_swaync
    did_something=true
fi

if [[ "$did_something" == "false" ]]; then
    echo "Nothing to do"
fi
