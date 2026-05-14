#!/usr/bin/env bash
# Locks the session via hyprlock.
# Switches to empty lock workspaces first, then restores everything after unlock.

USER_SETTINGS=~/.config/vutureland/hypr.lua/user_settings.lua

mon1=$(grep -oP '^mon1\s*=\s*"\K[^"]+' "$USER_SETTINGS" 2>/dev/null | head -1 || true)
mon2=$(grep -oP '^mon2\s*=\s*"\K[^"]+' "$USER_SETTINGS" 2>/dev/null | head -1 || true)

# In Hyprland Lua mode, dispatch args must be valid Lua expressions:
#   focusmonitor("DP-2")  →  hl.dispatch(focusmonitor("DP-2"))  ✓
#   workspace(111)        →  hl.dispatch(workspace(111))        ✓
dispatch() { hyprctl dispatch "$@"; }
focusmon() { dispatch "focusmonitor(\"$1\")"; }
ws()       { dispatch "workspace($1)"; }

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
