#!/usr/bin/env bash
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)/assets/scripts/lib/env.sh"

THEME="$VUTURELAND_DIR/rofi/clipvault.rasi"

selected=$(clipvault list | rofi -dmenu -p "󰅍 " -config "$THEME")

[[ -z "$selected" ]] && exit 0

clipvault get "$selected" | wl-copy
