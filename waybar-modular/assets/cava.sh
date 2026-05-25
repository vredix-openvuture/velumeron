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

playing=false
last_check=0
last_active=$(date +%s)
idle_shown=false

cava -p "$CONFIG" | while true; do
    now=$(date +%s)

    # re-check playerctl once per second
    if (( now > last_check )); then
        last_check=$now
        if playerctl -i firefox status 2>/dev/null | grep -q "^Playing"; then
            playing=true
        else
            playing=false
        fi
    fi

    if IFS=';' read -t 1 -ra vals; then
        out=""
        for v in "${vals[@]}"; do
            v="${v//[$'\r\n']/}"
            [[ -z "$v" ]] && continue
            out+="${ICONS[$v]:-▁}"
        done
        [[ -z "$out" ]] && continue

        if $playing; then
            # music playing — reset idle timer, show bars
            last_active=$now
            idle_shown=false
            echo "$out"
        elif (( now - last_active < IDLE_TIMEOUT )); then
            # grace period — still show bars (they'll fade naturally)
            echo "$out"
        elif ! $idle_shown; then
            echo "$IDLE_TEXT"
            idle_shown=true
        fi
    else
        rc=$?
        (( rc > 128 )) || break  # EOF → exit; timeout → continue
        if ! $playing && (( now - last_active >= IDLE_TIMEOUT )) && ! $idle_shown; then
            echo "$IDLE_TEXT"
            idle_shown=true
        fi
    fi
done
