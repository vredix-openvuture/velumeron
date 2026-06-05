import os, re

# System/package directory — set by VUTURELAND_DIR env var (AUR install) or
# auto-detected as the directory containing this file's parent (dev mode).
_xdg_cfg = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
VTL      = os.environ.get("VUTURELAND_DIR") or os.path.join(os.path.dirname(__file__), "..")
VTL      = os.path.realpath(VTL)

# Per-user config/data directory — always ~/.config/vutureland (or XDG equivalent).
VTL_USER = os.environ.get("VUTURELAND_USER_DIR") or os.path.join(_xdg_cfg, "vutureland")

# ── System paths (package files, never user-edited) ──────────────────────────
WALLPAPER_H       = f"{VTL}/assets/wallpaper/horizontal"
WALLPAPER_V       = f"{VTL}/assets/wallpaper/vertical"
THEME_NAMES       = f"{VTL}/assets/wallpaper/theme-names.txt"
SET_WP            = f"{VTL}/assets/scripts/wallpaper-set.sh"
GEN_THUMBS        = f"{VTL}/rofi/assets/generate-thumbnail.sh"
WALLUST_FIXED_DIR = f"{VTL}/wallust/fixed_colors"
LAUNCH_WAYBAR     = f"{VTL}/assets/scripts/launch-waybar.sh"
SETS_JSON         = f"{VTL}/assets/wallpaper/sets.json"
HYPRLOCK_THEMES   = f"{VTL}/hypr.lua/hyprlock-themes"
HYPRLOCK_BLACK_WP = f"{VTL}/assets/wallpaper/hyprlock/pure-black.jpg"
POWERMODE_SH      = f"{VTL}/assets/scripts/powermode.sh"

# ── User paths (per-user state, generated output, preferences) ───────────────
USER_SETTINGS     = f"{VTL_USER}/hypr.lua/user_settings.lua"
WALLUST_MODE_FILE = f"{VTL_USER}/wallust/color-mode"
HYPRLOCK_CONF     = f"{VTL_USER}/hypr.lua/hyprlock.conf"
HYPRIDLE_CONF     = f"{VTL_USER}/hypr.lua/hypridle.conf"
WALLPAPER_OLD     = f"{VTL_USER}/assets/wallpaper/old_wallpaper"

# ── Cache paths ───────────────────────────────────────────────────────────────
_xdg_cache    = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
THUMB_DIR     = f"{_xdg_cache}/vutureland/wallpaper-thumbs"
HYPRLOCK_THUMB = f"{_xdg_cache}/vutureland/hyprlock-thumbs"

VIDEO_EXTS = {'.mp4', '.webm', '.mkv', '.avi', '.mov'}
IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.webp'}
ALL_EXTS   = IMAGE_EXTS | VIDEO_EXTS

# Allow optional trailing chars after type suffix (e.g. "ver copy" from bad filenames)
ID_RE = re.compile(r'^(?:vwp|wp)_([a-zA-Z0-9]+)_(vid_hor|hor|ver)(?:\s.*)?$')

TRANSFORM_LABELS = [
    'Normal (0)', '90° (1)', '180° (2)', '270° (3)',
    'Flipped (4)', 'Flipped 90° (5)', 'Flipped 180° (6)', 'Flipped 270° (7)',
]
