#!/usr/bin/env bash
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)/assets/scripts/lib/env.sh"

THEME="$VELUMERON_USER_DIR/rofi/clipvault.rasi"

selected=$(clipvault list | rofi -dmenu -p "󰅍 " -config "$THEME")

[[ -z "$selected" ]] && exit 0

printf '%s' "$(clipvault get "$selected")" | wl-copy

# Show OSD confirmation
_FIFO="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/velumeron-osd.fifo"
[[ -p "$_FIFO" ]] && printf 'notify edit-copy-symbolic Copied to clipboard\n' > "$_FIFO"
