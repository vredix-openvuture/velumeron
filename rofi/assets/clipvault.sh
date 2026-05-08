#!/usr/bin/env bash

THEME="$HOME/.config/vutureland/rofi/clipvault.rasi"

selected=$(clipvault list | rofi -dmenu -p "󰅍 " -config "$THEME")

[[ -z "$selected" ]] && exit 0

clipvault get "$selected" | wl-copy
