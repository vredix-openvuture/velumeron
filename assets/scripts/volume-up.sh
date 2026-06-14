#!/usr/bin/env bash
# Raise volume by 5%, then clamp to 100% so it never goes above.
pactl set-sink-volume @DEFAULT_SINK@ +5%
vol=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '\d+(?=%)' | head -1)
if (( vol > 100 )); then
    pactl set-sink-volume @DEFAULT_SINK@ 100%
fi
