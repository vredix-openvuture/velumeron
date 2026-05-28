#!/usr/bin/env bash

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export DISPLAY="${DISPLAY:-:0}"

ICONS="~/.config/vutureland/assets/icons"
THEME="~/.config/vutureland/rofi/session-menu.rasi"

entries() {
    printf "Settings\0icon\x1f%s\n" "${ICONS}/vuture.png"
    printf "Suspend\0icon\x1f%s\n"  "${ICONS}/suspend.png"
    printf "Logout\0icon\x1f%s\n"   "${ICONS}/logout.png"
    printf "Reboot\0icon\x1f%s\n"   "${ICONS}/reboot.png"
    printf "Shutdown\0icon\x1f%s\n" "${ICONS}/shutdown.png"
}

choice=$(entries | rofi -dmenu -p "" -theme "$THEME")

case "$choice" in
    Settings) python ~/.config/vutureland/gui/main.py ;;
    Suspend)  ~/.config/vutureland/assets/scripts/launch-hyprlock.sh & sleep 4 && systemctl suspend ;;
    Shutdown) systemctl poweroff ;;
    Logout)   hyprctl dispatch exit ;;
    Reboot)   systemctl reboot ;;
esac
