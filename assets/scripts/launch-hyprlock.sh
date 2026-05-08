#!/usr/bin/env fish

# Locks the session via hyprlock.
# Switches to empty lock workspaces first, then restores everything after unlock.

set monitors_conf ~/.config/vutureland/hypr/monitors.conf

set mon1 (grep '^\$mon1' $monitors_conf | string replace -r '^\$mon1\s*=\s*' '' | string trim)
set mon2 (grep '^\$mon2' $monitors_conf | string replace -r '^\$mon2\s*=\s*' '' | string trim)

# Remember playback state and pause
set was_playing (playerctl status 2>/dev/null)
if test "$was_playing" = "Playing"
    playerctl pause
end

# Remember current workspaces
set ws1 (hyprctl monitors -j | jq -r '.[] | select(.name == "'$mon1'") | .activeWorkspace.id')

# Switch to lock workspaces
hyprctl dispatch focusmonitor $mon1
hyprctl dispatch workspace 111

# If mon2 exists
if test -n "$mon2"
    set ws2 (hyprctl monitors -j | jq -r '.[] | select(.name == "'$mon2'") | .activeWorkspace.id')
    hyprctl dispatch focusmonitor $mon2
    hyprctl dispatch workspace 112
end

sleep 0.4


##############

hyprlock -c ~/.config/vutureland/hypr/hyprlock.conf

##############


# Restore workspaces
hyprctl dispatch focusmonitor $mon1
hyprctl dispatch workspace $ws1

if test -n "$mon2"
    hyprctl dispatch focusmonitor $mon2
    hyprctl dispatch workspace $ws2
end

# Resume playback only if something was playing before
if test "$was_playing" = "Playing"
    playerctl play
end