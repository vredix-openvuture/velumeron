#!/usr/bin/env bash

PROFILES=(power-saver balanced performance)

_gamemode_active() {
    gamemoded -s 2>/dev/null | grep -q "is active"
}

_next() {
    local current
    current=$(powerprofilesctl get)
    local n=${#PROFILES[@]}
    for i in "${!PROFILES[@]}"; do
        if [[ "${PROFILES[$i]}" == "$current" ]]; then
            echo "${PROFILES[$(( (i + 1) % n ))]}"
            return
        fi
    done
    echo "${PROFILES[0]}"
}

_label() {
    if _gamemode_active; then
        echo "󰊴 GameMode"
        return
    fi
    case "$(powerprofilesctl get)" in
        performance) echo "󰡴 Performance" ;;
        balanced)    echo "󰌪 Balanced"    ;;
        power-saver) echo "󰞀 Powersaver"  ;;
        *)           echo "? Unknown"     ;;
    esac
}

case "${1:-}" in
    --active)
        powerprofilesctl get
        ;;
    --label)
        _label
        ;;
    --gamemode)
        _gamemode_active && echo "active" || echo "inactive"
        ;;
    --set_performance)
        powerprofilesctl set performance
        ;;
    --set_balanced)
        powerprofilesctl set balanced
        ;;
    --set_powersaver)
        powerprofilesctl set power-saver
        ;;
    --set_gamemode)
        gamemoded -r 2>/dev/null
        ;;
    force-performance)
        powerprofilesctl set performance
        ;;
    force-balanced)
        powerprofilesctl set balanced
        ;;
    *)
        if _gamemode_active; then
            echo "GameMode active – profile will not be changed"
            exit 1
        fi
        powerprofilesctl set "$(_next)"
        ;;
esac