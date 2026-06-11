#!/usr/bin/env bash
# Vutureland – Waybar hover-to-show daemon (Hyprland), position- & monitor-aware.
#
# Hides Waybar and reveals it while the cursor sits at the screen edge where a
# bar actually lives. Works for top/bottom/left/right bars and any monitor
# layout: the trigger zones are derived per bar from `hyprctl monitors`
# geometry (scale-corrected, in layout coords) and the bar positions in the
# merged Waybar config.
#
# Note: Waybar's SIGUSR1 toggles *all* bars in the process at once, so on a
# client whose bars sit on different edges, hovering one edge reveals them all.
#
# Started/stopped by launch-waybar.sh based on the .hover-hide flag file.
# Exits on its own when Waybar goes away (e.g. on the next restart).
#
#   $1  path to the merged Waybar config (array of bar objects carrying
#       "output" + "position"). Defaults to /tmp/waybar-merged-config.json.

set -u

REVEAL_AT=${WAYBAR_HOVER_REVEAL:-8}     # px from the edge that triggers a reveal
KEEP_PAD=${WAYBAR_HOVER_KEEP:-44}       # while shown, keep visible within this band (≈ bar size)
INTERVAL=${WAYBAR_HOVER_INTERVAL:-0.12} # cursor poll interval (seconds)
MERGED=${1:-/tmp/waybar-merged-config.json}

command -v hyprctl >/dev/null 2>&1 || exit 0
command -v jq      >/dev/null 2>&1 || exit 0

visible=1   # Waybar comes up visible right after launch

toggle() { pkill -SIGUSR1 -x waybar 2>/dev/null; }
show()   { (( visible )) || { toggle; visible=1; }; }
hide()   { (( visible )) && { toggle; visible=0; }; }

# One "pos mx my mw mh" line per bar, resolving its output to that monitor's
# effective geometry (scale-corrected) in Hyprland layout coordinates.
build_zones() {
    local mon_json
    mon_json=$(hyprctl monitors -j 2>/dev/null) || return 1
    [[ -f "$MERGED" ]] || return 1
    jq -r --argjson mons "$mon_json" '
        ($mons | map({key:.name, value:{x:.x, y:.y,
                       w:((.width/.scale)|round), h:((.height/.scale)|round)}})
                | from_entries) as $g
        | .[]
        | (.output // empty) as $out
        | (.position // "top") as $pos
        | ($g[$out]) as $m
        | select($m != null)
        | "\($pos) \($m.x) \($m.y) \($m.w) \($m.h)"
    ' "$MERGED" 2>/dev/null
}

# True (0) if the cursor (x,y) is within `pad` px of any bar's edge.
in_zone() {
    local x=$1 y=$2 pad=$3 pos mx my mw mh
    while read -r pos mx my mw mh; do
        [[ -z "${pos:-}" ]] && continue
        case "$pos" in
            top)    (( x>=mx && x<mx+mw && y>=my       && y<my+pad      )) && return 0 ;;
            bottom) (( x>=mx && x<mx+mw && y>my+mh-pad && y<my+mh       )) && return 0 ;;
            left)   (( y>=my && y<my+mh && x>=mx       && x<mx+pad      )) && return 0 ;;
            right)  (( y>=my && y<my+mh && x>mx+mw-pad && x<mx+mw       )) && return 0 ;;
        esac
    done <<< "$ZONES"
    return 1
}

# Wait for Waybar, then build the trigger zones from the live geometry.
for _ in $(seq 1 50); do pgrep -x waybar >/dev/null && break; sleep 0.1; done
ZONES=$(build_zones)
[[ -z "$ZONES" ]] && exit 0     # no resolvable bars → nothing to hide

sleep 0.3
hide

while pgrep -x waybar >/dev/null; do
    read -r x y < <(hyprctl cursorpos -j 2>/dev/null | jq -r '"\(.x|floor) \(.y|floor)"')
    if [[ ${x:-} =~ ^-?[0-9]+$ && ${y:-} =~ ^-?[0-9]+$ ]]; then
        if (( visible )); then
            in_zone "$x" "$y" "$KEEP_PAD" || hide
        else
            in_zone "$x" "$y" "$REVEAL_AT" && show
        fi
    fi
    sleep "$INTERVAL"
done
