#!/usr/bin/env bash

ICONS=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
IDLE_TEXT="we love music"
IDLE_TIMEOUT=10

CONFIG=$(mktemp /tmp/waybar-cava-XXXXXX.ini)
cat > "$CONFIG" << 'EOF'
[general]
framerate = 60
bars = 40

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
bar_delimiter = 59
EOF

cleanup() { rm -f "$CONFIG"; kill 0 2>/dev/null; }
trap cleanup EXIT INT TERM

last_activity=$(date +%s)
idle_shown=false

cava -p "$CONFIG" | while true; do
    if IFS=';' read -t 1 -ra vals; then
        out=""
        all_zero=true
        for v in "${vals[@]}"; do
            v="${v//[$'\r\n']/}"
            [[ -z "$v" ]] && continue
            [[ "$v" != "0" ]] && all_zero=false
            out+="${ICONS[$v]:-▁}"
        done
        [[ -z "$out" ]] && continue

        if ! $all_zero; then
            last_activity=$(date +%s)
            idle_shown=false
            echo "$out"
        else
            now=$(date +%s)
            if (( now - last_activity >= IDLE_TIMEOUT )) && ! $idle_shown; then
                echo "$IDLE_TEXT"
                idle_shown=true
            fi
        fi
    else
        rc=$?
        (( rc > 128 )) || break  # EOF → exit loop; timeout → check idle
        now=$(date +%s)
        if (( now - last_activity >= IDLE_TIMEOUT )) && ! $idle_shown; then
            echo "$IDLE_TEXT"
            idle_shown=true
        fi
    fi
done
