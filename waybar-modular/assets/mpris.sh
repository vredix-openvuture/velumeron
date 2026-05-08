#!/bin/bash
# ~/.config/waybar/scripts/mpris.sh

status=$(playerctl status 2>/dev/null)

if [[ "$status" == "Playing" || "$status" == "Paused" ]]; then
    title=$(playerctl metadata title 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    artist=$(playerctl metadata artist 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    position=$(playerctl position --format '{{duration(position)}}' 2>/dev/null)
    length=$(playerctl metadata --format '{{duration(mpris:length)}}' 2>/dev/null)
    [[ "$status" == "Paused" ]] && icon="" || icon="▶"

    printf '{"text":"%s  %s","tooltip":"%s\\n\\n%s / %s"}\n' "$icon" "$title" "$artist" "$position" "$length"
else
    printf '{"text":"lets listen","tooltip":"no active playback"}\n'
fi