#!/usr/bin/env bash
#
# Bluetooth connection notifier — runs as a systemd user service.
#
# Service file: ~/.config/systemd/user/bt-notify.service
#   [Unit]
#   Description=Bluetooth connection notifications
#   After=bluetooth.target
#
#   [Service]
#   ExecStart=%h/.config/vutureland/assets/scripts/bt-notify.sh
#   Restart=always
#   RestartSec=3
#   Environment=DISPLAY=:0
#
#   [Install]
#   WantedBy=default.target
#
# Enable and start:
#   systemctl --user daemon-reload
#   systemctl --user enable --now bt-notify.service

RE_PATH='path=/org/bluez/[^/]+/dev_([0-9A-F_]+)'

last_event=""

dbus-monitor --system \
    "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path_namespace='/org/bluez'" \
| while IFS= read -r line; do
    if [[ "$line" =~ $RE_PATH ]]; then
        mac="${BASH_REMATCH[1]//_/:}"
    fi
    if [[ -n "$mac" && "$line" == *'"Connected"'* ]]; then
        read -r val_line
        if [[ "$val_line" == *"true"* ]]; then
            event="${mac}:connected"
            if [[ "$event" != "$last_event" ]]; then
                name=$(bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/^\s+Name:/ {print $2; exit}')
                notify-send -i "$HOME/.config/vutureland/assets/icons/bluetooth.png" "Bluetooth" "Connected to ${name:-$mac}"
                last_event="$event"
            fi
            mac=""
        elif [[ "$val_line" == *"false"* ]]; then
            event="${mac}:disconnected"
            if [[ "$event" != "$last_event" ]]; then
                name=$(bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/^\s+Name:/ {print $2; exit}')
                notify-send -i "$HOME/.config/vutureland/assets/icons/bluetooth.png" "Bluetooth" "Disconnected from ${name:-$mac}"
                last_event="$event"
            fi
            mac=""
        fi
    fi
done
