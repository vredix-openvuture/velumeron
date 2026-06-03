-- ═══════════════════════════════════════════════════════
-- Application variables — common across all devices
-- ═══════════════════════════════════════════════════════

-- Scripts live in the read-only package dir (VTL_DIR).
-- Configs that have to be read alongside wallust-written colour files
-- (kitty.conf, rofi *.rasi) live in the user dir (VTL_USER_DIR), which
-- welcome_to_vutureland.sh seeds from the package on first run.

desktop_shell  = VTL_DIR      .. "/assets/scripts/launch-waybar.sh"
notify_service = "swaync"
clipboard      = VTL_USER_DIR .. "/rofi/assets/clipvault.sh"

launcher       = "rofi -show drun -config "      .. VTL_USER_DIR .. "/rofi/launcher.rasi"
theme_switch   = "rofi -show wallpaper -config " .. VTL_USER_DIR .. "/rofi/wallpaper-switcher.rasi"
terminal       = "kitty -c "                     .. VTL_USER_DIR .. "/kitty/kitty.conf"
notifications  = "swaync-client -R -rs -t"
screenshot_cmd = "hyprshot -z --mode region --output-folder ~/Bilder/Screenshots"

on_sleep       = "systemctl suspend"
on_lock        = VTL_DIR      .. "/assets/scripts/launch-hyprlock.sh"
session_menu   = VTL_USER_DIR .. "/rofi/assets/session-menu.sh"
