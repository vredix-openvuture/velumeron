-- ═══════════════════════════════════════════════════════
-- Application variables — common across all devices
-- ═══════════════════════════════════════════════════════

desktop_shell  = VTL_DIR .. "/assets/scripts/launch-waybar.sh"
notify_service = "swaync"
clipboard      = VTL_DIR .. "/rofi/assets/clipvault.sh"

launcher       = "rofi -show drun -config "     .. VTL_DIR .. "/rofi/launcher.rasi"
theme_switch   = "rofi -show wallpaper -config " .. VTL_DIR .. "/rofi/wallpaper-switcher.rasi"
terminal       = "kitty -c "                    .. VTL_DIR .. "/kitty/kitty.conf"
notifications  = "swaync-client -R -rs -t"
screenshot_cmd = "hyprshot -z --mode region --output-folder ~/Bilder/Screenshots"

on_sleep       = "systemctl suspend"
on_lock        = VTL_DIR .. "/assets/scripts/launch-hyprlock.sh"
session_menu   = VTL_DIR .. "/rofi/assets/session-menu.sh"
