#!/usr/bin/env bash
# Central path library — source this at the top of every velumeron script:
#
#   source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"
#
# VELUMERON_DIR      — package/system directory (scripts, configs, assets)
#                       Auto-detected from this file's location. Can be
#                       overridden by setting the env var before sourcing.
# VELUMERON_USER_DIR — per-user data (generated output, user_settings, prefs)
#                       Always ${XDG_CONFIG_HOME:-~/.config}/velumeron.

if [[ -z "${VELUMERON_DIR:-}" ]]; then
    VELUMERON_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../.." && pwd)"
fi
export VELUMERON_DIR

VELUMERON_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/velumeron"
export VELUMERON_USER_DIR

# Effective wallpaper dirs — a user-set custom path (gui/settings.json) if it
# exists, otherwise the bundled dir. Mirrors constants.wallpaper_dir() in the GUI
# so the switcher/thumbnailer/wallpaper-set all honour a client's own folder.
_vtl_wallpaper_dir() {
    local key="$1" fallback="$2" custom=""
    local gs="$VELUMERON_USER_DIR/gui/settings.json"
    if [[ -f "$gs" ]] && command -v jq >/dev/null 2>&1; then
        custom=$(jq -r --arg k "$key" '.[$k] // ""' "$gs" 2>/dev/null || true)
        custom="${custom/#\~/$HOME}"
    fi
    if [[ -n "$custom" && -d "$custom" ]]; then printf '%s' "$custom"
    else printf '%s' "$fallback"; fi
}
WALLPAPER_DIR_H="$(_vtl_wallpaper_dir wallpaper_dir_hor "$VELUMERON_DIR/assets/wallpaper/horizontal")"
WALLPAPER_DIR_V="$(_vtl_wallpaper_dir wallpaper_dir_ver "$VELUMERON_DIR/assets/wallpaper/vertical")"
export WALLPAPER_DIR_H WALLPAPER_DIR_V
