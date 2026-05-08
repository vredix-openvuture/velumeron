#!/usr/bin/env bash

LAST_PLAYER_FILE="/tmp/waybar-last-player"

BROWSER_PLAYERS=("firefox" "chromium" "chrome" "brave" "opera")

is_browser() {
    local short="${1%%.*}"
    for b in "${BROWSER_PLAYERS[@]}"; do
        [[ "$short" == "$b" ]] && return 0
    done
    return 1
}

real_playing=()
while IFS= read -r p; do
    is_browser "$p" && continue
    [[ "$(playerctl -p "$p" status 2>/dev/null)" == "Playing" ]] && real_playing+=("$p")
done < <(playerctl -l 2>/dev/null)

if [[ ${#real_playing[@]} -gt 0 ]]; then
    printf '%s\n' "${real_playing[@]}" > "$LAST_PLAYER_FILE"
    playerctl -a pause
else
    while IFS= read -r last; do
        [[ -n "$last" ]] && playerctl -l 2>/dev/null | grep -qxF "$last" \
            && playerctl -p "$last" play
    done < "$LAST_PLAYER_FILE" 2>/dev/null
fi
