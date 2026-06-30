#!/usr/bin/env bash
# Locks the session via hyprlock.
# Switches to empty lock workspaces first, then restores everything after unlock.
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

USER_SETTINGS="$VELUMERON_USER_DIR/hypr.lua/user_settings.lua"

mon1=$(grep -oP '^mon1\s*=\s*"\K[^"]+' "$USER_SETTINGS" 2>/dev/null | head -1 || true)
mon2=$(grep -oP '^mon2\s*=\s*"\K[^"]+' "$USER_SETTINGS" 2>/dev/null | head -1 || true)

# In Hyprland Lua mode, dispatch args are evaluated as Lua inside hl.dispatch().
# The correct form uses hl.dsp actions — same API as in keybinds.lua:
#   hl.dsp.focus({ monitor = "DP-2" })   →  focusmonitor
#   hl.dsp.focus({ workspace = 111 })    →  switch workspace
focusmon() { hyprctl dispatch "hl.dsp.focus({monitor=\"${1}\"})"; }
ws()       { hyprctl dispatch "hl.dsp.focus({workspace=${1}})"; }

# Remember playback state and pause
was_playing=$(playerctl status 2>/dev/null || true)
[[ "$was_playing" == "Playing" ]] && playerctl pause

# Remember current workspaces and switch to lock workspaces
ws1=$(hyprctl monitors -j | jq -r --arg m "$mon1" '.[] | select(.name == $m) | .activeWorkspace.id')
focusmon "$mon1"
ws 111

if [[ -n "$mon2" ]]; then
    ws2=$(hyprctl monitors -j | jq -r --arg m "$mon2" '.[] | select(.name == $m) | .activeWorkspace.id')
    focusmon "$mon2"
    ws 112
fi

sleep 0.4

# hyprlock reads ~/.config/hypr/hyprlock.conf (symlink seeded by setup);
# rofi-hyprlock.sh / the GUI write the active theme to
# $VELUMERON_USER_DIR/hypr.lua/hyprlock.conf with this machine's monitors.
# Self-heal: if that conf references none of the current monitors (e.g. it was
# shipped/synced with another machine's names), regenerate it now so the
# wallpaper actually appears on this machine's monitor.
ACTIVE_CONF="$VELUMERON_USER_DIR/hypr.lua/hyprlock.conf"
_cur_mons=$(hyprctl monitors -j | jq -r '.[].name' | paste -sd'|')
if [[ -n "$_cur_mons" ]] && \
   ! grep -qE "monitor[[:space:]]*=[[:space:]]*($_cur_mons)([[:space:]]|\$)" "$ACTIVE_CONF" 2>/dev/null; then
    "$VELUMERON_DIR/assets/scripts/apply-hyprlock-theme.sh" || true
fi

hyprlock

# Restore workspaces
focusmon "$mon1"
ws "$ws1"

if [[ -n "$mon2" ]]; then
    focusmon "$mon2"
    ws "$ws2"
fi

# Resume playback only if something was playing before
[[ "$was_playing" == "Playing" ]] && playerctl play
