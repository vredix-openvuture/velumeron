import os, re

VTL           = os.path.expanduser("~/.config/vutureland")
WALLPAPER_H   = f"{VTL}/assets/wallpaper/horizontal"
WALLPAPER_V   = f"{VTL}/assets/wallpaper/vertical"
THUMB_DIR     = os.path.expanduser("~/.cache/vutureland/wallpaper-thumbs")
THEME_NAMES   = f"{VTL}/assets/wallpaper/theme-names.txt"
SET_WP        = f"{VTL}/assets/scripts/wallpaper-set.sh"
GEN_THUMBS    = f"{VTL}/rofi/assets/generate-thumbnail.sh"
USER_SETTINGS = f"{VTL}/hypr.lua/user_settings.lua"
BARS_JSON     = f"{VTL}/waybar-modular/groups/bars.json"
GROUPS_JSON   = f"{VTL}/waybar-modular/groups/groups-dock-top.json"
LAUNCH_WAYBAR = f"{VTL}/assets/scripts/launch-waybar.sh"

VIDEO_EXTS = {'.mp4', '.webm', '.mkv', '.avi', '.mov'}
IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.webp'}
ALL_EXTS   = IMAGE_EXTS | VIDEO_EXTS

# Allow optional trailing chars after type suffix (e.g. "ver copy" from bad filenames)
ID_RE = re.compile(r'^(?:vwp|wp)_([a-zA-Z0-9]+)_(vid_hor|hor|ver)(?:\s.*)?$')

TRANSFORM_LABELS = [
    'Normal (0)', '90° (1)', '180° (2)', '270° (3)',
    'Flipped (4)', 'Flipped 90° (5)', 'Flipped 180° (6)', 'Flipped 270° (7)',
]

AVAILABLE_MODULES = [
    'clock', 'battery', 'bluetooth', 'custom/cava', 'cpu', 'memory',
    'custom/menu-user', 'custom/mpris', 'custom/notification',
    'custom/performance', 'pulseaudio', 'pulseaudio/slider',
    'custom/separator', 'hyprland/submap', 'temperature#cpu',
    'temperature#gpu', 'tray', 'user', 'custom/vpn', 'hyprland/workspaces',
    'group/tray_drawer', 'group/audio_drawer', 'group/performance_drawer',
]
