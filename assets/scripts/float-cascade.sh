#!/usr/bin/env bash
# Floating windows on open or monitor change:
#   1. Clamp to 90% of monitor size (transform-aware)
#   2. (open only) Cascade (+40/+40) until no position collision

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

_check_collision() {
    local addr="$1" ax="$2" ay="$3" aw="$4" ah="$5"
    hyprctl clients -j | jq \
        --arg  addr "$addr" \
        --argjson ax "$ax" --argjson ay "$ay" \
        --argjson aw "$aw" --argjson ah "$ah" \
        '[.[] | select(
            .address != $addr and
            .at[0]   == $ax   and .at[1]   == $ay   and
            .size[0] == $aw   and .size[1] == $ah
        )] | length'
}

# Returns 0 if no resize needed, otherwise resizes the window.
# Updates aw/ah with the new values (nameref).
_clamp_to_monitor() {
    local addr="$1" mon_id="$2"
    local -n _aw="$3" _ah="$4"

    local monitor transform mon_w mon_h eff_w eff_h max_w max_h new_w new_h
    monitor=$(hyprctl monitors -j | jq --argjson id "$mon_id" '.[] | select(.id == $id)')
    transform=$(printf '%s' "$monitor" | jq -r '.transform')
    mon_w=$(printf '%s'     "$monitor" | jq -r '.width')
    mon_h=$(printf '%s'     "$monitor" | jq -r '.height')

    if (( transform % 2 == 1 )); then
        eff_w=$mon_h; eff_h=$mon_w
    else
        eff_w=$mon_w; eff_h=$mon_h
    fi

    max_w=$(( eff_w * 9 / 10 ))
    max_h=$(( eff_h * 9 / 10 ))

    new_w=$_aw; new_h=$_ah
    [[ $_aw -gt $max_w ]] && new_w=$max_w
    [[ $_ah -gt $max_h ]] && new_h=$max_h

    if [[ $new_w -ne $_aw || $new_h -ne $_ah ]]; then
        hyprctl dispatch resizewindowpixel exact "$new_w" "$new_h",address:"$addr"
        _aw=$new_w; _ah=$new_h
    fi
}

socat -U - UNIX-CONNECT:"$SOCKET" | while IFS= read -r line; do
    event="${line%%>>*}"
    [[ "$event" != "openwindow" && "$event" != "movewindow" ]] && continue

    data="${line#*>>}"
    raw_addr="${data%%,*}"
    addr="0x${raw_addr#0x}"   # normalize: ensure 0x prefix appears exactly once

    sleep 0.1

    win=$(hyprctl clients -j | jq --arg a "$addr" '.[] | select(.address == $a)')
    [[ -z "$win" ]] && continue

    floating=$(printf '%s' "$win" | jq -r '.floating')
    [[ "$floating" != "true" ]] && continue

    ax=$(printf '%s' "$win" | jq -r '.at[0]')
    ay=$(printf '%s' "$win" | jq -r '.at[1]')
    aw=$(printf '%s' "$win" | jq -r '.size[0]')
    ah=$(printf '%s' "$win" | jq -r '.size[1]')
    mon_id=$(printf '%s' "$win" | jq -r '.monitor')

    _clamp_to_monitor "$addr" "$mon_id" aw ah

    # Cascade only on open, not on monitor change
    if [[ "$event" == "openwindow" ]]; then
        collision=$(_check_collision "$addr" "$ax" "$ay" "$aw" "$ah")
        while [[ "$collision" -gt 0 ]]; do
            ax=$(( ax + 40 ))
            ay=$(( ay + 40 ))
            hyprctl dispatch movewindowpixel exact "$ax" "$ay",address:"$addr"
            collision=$(_check_collision "$addr" "$ax" "$ay" "$aw" "$ah")
        done
    fi
done
