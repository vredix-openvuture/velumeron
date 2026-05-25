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

IDLE_TEXT="we love music"
IDLE_TIMEOUT=10

cleanup() { rm -f "$CONFIG"; kill 0 2>/dev/null; }
trap cleanup EXIT INT TERM

last_active=$SECONDS
idle_shown=false

cava -p "$CONFIG" | while IFS=';' read -ra vals; do
    out=""
    all_zero=true
    for v in "${vals[@]}"; do
        v="${v//[$'\r\n']/}"
        [[ -z "$v" ]] && continue
        [[ "$v" != "0" ]] && all_zero=false
        out+="${ICONS[$v]:-▁}"
    done

    [[ -z "$out" ]] && continue

    if $all_zero; then
        if (( SECONDS - last_active >= IDLE_TIMEOUT )); then
            if ! $idle_shown; then
                echo "$IDLE_TEXT"
                idle_shown=true
            fi
        fi
    else
        last_active=$SECONDS
        idle_shown=false
        echo "$out"
    fi
done
