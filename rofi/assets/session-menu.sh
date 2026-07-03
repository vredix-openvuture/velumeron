#!/usr/bin/env bash
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)/assets/scripts/lib/env.sh"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export DISPLAY="${DISPLAY:-:0}"

ICONS="$VELUMERON_DIR/assets/icons"
THEME="$VELUMERON_USER_DIR/rofi/session-menu.rasi"

entries() {
    printf "Settings\0icon\x1f%s\n" "${ICONS}/vuture.png"
    printf "Suspend\0icon\x1f%s\n"  "${ICONS}/suspend.png"
    printf "Logout\0icon\x1f%s\n"   "${ICONS}/logout.png"
    printf "Reboot\0icon\x1f%s\n"   "${ICONS}/reboot.png"
    printf "Shutdown\0icon\x1f%s\n" "${ICONS}/shutdown.png"
}

choice=$(entries | rofi -dmenu -p "" -theme "$THEME")

case "$choice" in
    Settings) setsid "$VELUMERON_DIR/bin/velumeron" -t >/dev/null 2>&1 & ;;
    # Locking on suspend is hypridle's job (before_sleep_cmd + inhibit_sleep=3) —
    # launching hyprlock here as well raced the suspend and crashed on resume.
    Suspend)  systemctl suspend ;;
    Shutdown) systemctl poweroff ;;
    Logout)   hyprctl dispatch exit ;;
    Reboot)   systemctl reboot ;;
esac
