#!/usr/bin/env bash
# Cascade floating windows on open: offset +40/+40 until no position collision.
# Size clamping (90% of monitor) is handled by the float_clamp window rule.

SOCKET1="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock"
SOCKET2="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

# Send a raw IPC command directly to Hyprland, bypassing the Lua evaluator.
_hypr() { printf '%s' "$1" | socat -u - "UNIX-CONNECT:$SOCKET1"; }

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

socat -U - "UNIX-CONNECT:$SOCKET2" | while IFS= read -r line; do
    event="${line%%>>*}"
    [[ "$event" != "openwindow" ]] && continue

    data="${line#*>>}"
    raw_addr="${data%%,*}"
    addr="0x${raw_addr#0x}"

    sleep 0.1

    win=$(hyprctl clients -j | jq --arg a "$addr" '.[] | select(.address == $a)')
    [[ -z "$win" ]] && continue

    floating=$(printf '%s' "$win" | jq -r '.floating')
    [[ "$floating" != "true" ]] && continue

    ax=$(printf '%s' "$win" | jq -r '.at[0]')
    ay=$(printf '%s' "$win" | jq -r '.at[1]')
    aw=$(printf '%s' "$win" | jq -r '.size[0]')
    ah=$(printf '%s' "$win" | jq -r '.size[1]')

    collision=$(_check_collision "$addr" "$ax" "$ay" "$aw" "$ah")
    while [[ "$collision" -gt 0 ]]; do
        ax=$(( ax + 40 ))
        ay=$(( ay + 40 ))
        _hypr "dispatch/movewindowpixel/exact ${ax} ${ay},address:${addr}"
        collision=$(_check_collision "$addr" "$ax" "$ay" "$aw" "$ah")
    done
done
