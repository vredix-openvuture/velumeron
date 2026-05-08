#!/usr/bin/env bash

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export DISPLAY="${DISPLAY:-:0}"

THEME="~/.config/vutureland/rofi/active-players.rasi"

declare -A PLAYER_NAMES=(
    [firefox]="Firefox"
    [chromium]="Chromium"
    [chrome]="Chrome"
    [spotify]="Spotify"
    [spotify_player]="Spotify"
    [vlc]="VLC"
    [mpv]="mpv"
    [rhythmbox]="Rhythmbox"
    [clementine]="Clementine"
    [elisa]="Elisa"
    [cantata]="Cantata"
    [strawberry]="Strawberry"
)

LABELS=()
PLAYERS=()

while IFS= read -r player; do
    status=$(playerctl -p "$player" status 2>/dev/null)
    case "$status" in
        Playing) icon="▶" ;;
        Paused)  icon="󰏤" ;;
        *)       icon="■" ;;
    esac

    raw="${player%%.*}"
    name="${PLAYER_NAMES[$raw]:-${raw^}}"

    LABELS+=("$icon  $name")
    PLAYERS+=("$player")
done < <(playerctl -l 2>/dev/null)

[[ ${#LABELS[@]} -eq 0 ]] && exit 0

choice=$(printf '%s\n' "${LABELS[@]}" | rofi -dmenu -p "Player" -theme "$THEME")

[[ -z "$choice" ]] && exit 0

for i in "${!LABELS[@]}"; do
    if [[ "${LABELS[$i]}" == "$choice" ]]; then
        playerctl -p "${PLAYERS[$i]}" play-pause
        break
    fi
done
