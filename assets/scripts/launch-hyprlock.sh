#!/usr/bin/env bash
# Locks the session via hyprlock.
# Switches to empty lock workspaces first, then restores everything after unlock.
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

USER_SETTINGS="$VUTURELAND_USER_DIR/hypr.lua/user_settings.lua"

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
# rofi-hyprlock.sh writes the active theme to $VUTURELAND_USER_DIR/hypr.lua/hyprlock.conf
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
