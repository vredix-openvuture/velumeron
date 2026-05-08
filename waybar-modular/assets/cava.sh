#!/usr/bin/env bash

ICONS=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")

CONFIG=$(mktemp /tmp/waybar-cava-XXXXXX.ini)
cat > "$CONFIG" << 'EOF'
[general]
framerate = 30
bars = 14

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
bar_delimiter = 59
EOF

cleanup() { rm -f "$CONFIG"; kill 0 2>/dev/null; }
trap cleanup EXIT INT TERM

cava -p "$CONFIG" | while IFS=';' read -ra vals; do
    out=""
    for v in "${vals[@]}"; do
        v="${v//[$'\r\n']/}"
        [[ -z "$v" ]] && continue
        out+="${ICONS[$v]:-▁}"
    done
    [[ -n "$out" ]] && echo "$out"
done
