#!/usr/bin/env bash
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

launch_wlogout="wlogout -l $VELUMERON_DIR/wlogout/layout -C $VELUMERON_DIR/wlogout/style.css"
launch_waybar="waybar   -c $VELUMERON_DIR/waybar/config.json -s $VELUMERON_DIR/waybar/style.css"

# === Define flags ===
flag_wlogout=false
flag_waybar=false

# === Parse arguments ===
for arg in "$@"; do
    case "$arg" in
        --wlogout) flag_wlogout=true ;;
        --waybar)  flag_waybar=true  ;;
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

if [[ "$did_something" == "false" ]]; then
    echo "Nothing to do"
fi
