-- ═══════════════════════════════════════════════════════
-- Application variables — common across all devices
-- ═══════════════════════════════════════════════════════

desktop_shell  = "~/.config/vutureland/assets/scripts/launch-waybar.sh"
notify_service = "swaync"

launcher       = "rofi -show drun -config /home/vredix/.config/vutureland/rofi/launcher.rasi"
theme_switch   = "rofi -show wallpaper -config ~/.config/vutureland/rofi/wallpaper-switcher.rasi"
terminal       = "kitty -c ~/.config/vutureland/kitty/kitty.conf"
notifications  = "swaync-client -R -rs -t"
screenshot_cmd = "hyprshot -z --mode region --output-folder ~/Bilder/Screenshots"

on_sleep       = "systemctl suspend"
on_lock        = "~/.config/vutureland/assets/scripts/launch-hyprlock.sh"
session_menu   = "~/.config/vutureland/rofi/assets/session-menu.sh"
