#!/usr/bin/env bash
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)/assets/scripts/lib/env.sh"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export DISPLAY="${DISPLAY:-:0}"

THEME="$VUTURELAND_USER_DIR/rofi/bluetooth.rasi"
ICONS="$VUTURELAND_DIR/assets/icons"

# Sort priority: lower = higher up in list
type_priority() {
    case "$1" in
        audio-headphones)        echo 1 ;;
        audio-headset)           echo 2 ;;
        audio-card)              echo 3 ;;
        input-gaming)            echo 4 ;;
        input-keyboard)          echo 5 ;;
        input-mouse)             echo 6 ;;
        phone)                   echo 7 ;;
        computer)                echo 8 ;;
        *)                       echo 9 ;;
    esac
}

type_icon() {
    local type="$1" name="${2,,}"  # name lowercase for matching

    # Name-based overrides take priority
    case "$name" in
        *headphone*|*headset*|*earphone*|*earbud*|*airpod*)
            echo "$ICONS/headphones.png"; return ;;
        *soundbar*|*speaker*)
            echo "$ICONS/speaker.png"; return ;;
        *controller*|*gamepad*|*joystick*)
            echo "$ICONS/controller.png"; return ;;
    esac

    # Fallback: type-based
    case "$type" in
        audio-headphones|\
        audio-headset)           echo "$ICONS/headphones.png" ;;
        audio-card)              echo "$ICONS/bt-speaker.png"    ;;
        input-gaming)            echo "$ICONS/controller.png" ;;
        input-keyboard)          echo "$ICONS/bt-keyboard.png"   ;;
        input-mouse)             echo "$ICONS/bt-mouse.png"      ;;
        phone)                   echo "$ICONS/bt-phone.png"      ;;
        computer)                echo "$ICONS/bt-computer.png"   ;;
        *)                       echo "$ICONS/bt-device.png"     ;;
    esac
}

get_paired_devices() {
    bluetoothctl devices Paired 2>/dev/null | awk '{print $2}' | while read -r mac; do
        info=$(bluetoothctl info "$mac" 2>/dev/null)
        name=$(echo "$info" | awk -F': ' '/^\s+Name:/      {print $2; exit}')
        type=$(echo "$info" | awk -F': ' '/^\s+Icon:/      {print $2; exit}')
        conn=$(echo "$info" | awk        '/^\s+Connected:/ {print $2; exit}')
        [[ -z "$type" ]] && type="unknown"
        prio=$(type_priority "$type")
        printf '%s\t%s\t%s\t%s\t%s\n' "$prio" "$mac" "$name" "$type" "$conn"
    done | sort -t$'\t' -k1,1n -k3,3
}

show_main_menu() {
    LABELS=()
    MACS=()
    ICON_PATHS=()

    while IFS=$'\t' read -r _ mac name type conn; do
        [[ "$conn" == "yes" ]] && status="●" || status="○"
        LABELS+=("$status  $name")
        MACS+=("$mac")
        ICON_PATHS+=("$(type_icon "$type" "$name")")
    done < <(get_paired_devices)

    LABELS+=("  Pair New Device")
    MACS+=("__pair__")
    ICON_PATHS+=("$ICONS/reload.png")

    choice=$(
        for i in "${!LABELS[@]}"; do
            printf '%s\0icon\x1f%s\n' "${LABELS[$i]}" "${ICON_PATHS[$i]}"
        done | rofi -dmenu -p "Bluetooth" -theme "$THEME"
    )
    [[ -z "$choice" ]] && return

    for i in "${!LABELS[@]}"; do
        [[ "${LABELS[$i]}" != "$choice" ]] && continue
        mac="${MACS[$i]}"
        if [[ "$mac" == "__pair__" ]]; then
            pair_new_device
        else
            info=$(bluetoothctl info "$mac" 2>/dev/null)
            conn=$(echo "$info" | awk '/^\s+Connected:/ {print $2; exit}')
            if [[ "$conn" == "yes" ]]; then
                bluetoothctl disconnect "$mac" > /dev/null
            else
                bluetoothctl connect "$mac" > /dev/null
            fi
        fi
        break
    done
}

pair_new_device() {
    mapfile -t paired_macs < <(bluetoothctl devices Paired 2>/dev/null | awk '{print $2}')

    # Keep bluetoothctl alive as a coprocess so scanning stays active
    coproc BTCTL { bluetoothctl 2>/dev/null; }
    echo "scan on" >&"${BTCTL[1]}"
    sleep 1

    stop_scan() {
        echo "scan off" >&"${BTCTL[1]}" 2>/dev/null
        kill "${BTCTL_PID}" 2>/dev/null
        rm -f "$CHOICE_FILE"
    }
    trap stop_scan RETURN INT TERM

    CHOICE_FILE=$(mktemp)

    get_avail() {
        bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
            for pm in "${paired_macs[@]}"; do
                [[ "$mac" == "$pm" ]] && continue 2
            done
            [[ -n "$name" ]] && echo "$mac $name"
        done
    }

    while true; do
        AVAIL_LABELS=()
        AVAIL_MACS=()
        while read -r mac name; do
            AVAIL_MACS+=("$mac")
            AVAIL_LABELS+=("$name")
        done < <(get_avail)

        printf '%s\n' "${AVAIL_LABELS[@]}" \
            | rofi -dmenu -p "  Pair Device" -theme "$THEME" \
                -mesg "Scanning for devices…" > "$CHOICE_FILE" &
        ROFI_PID=$!

        # Watch for new devices while Rofi is open
        snapshot=$(get_avail)
        while kill -0 "$ROFI_PID" 2>/dev/null; do
            current=$(get_avail)
            if [[ "$current" != "$snapshot" ]]; then
                kill "$ROFI_PID" 2>/dev/null
                break
            fi
            sleep 1
        done

        wait "$ROFI_PID"
        rofi_exit=$?
        choice=$(cat "$CHOICE_FILE")

        # Exit code 1 = user pressed Escape
        [[ $rofi_exit -eq 1 ]] && break
        # Killed by watcher (new device) = reopen
        [[ -z "$choice" ]] && continue

        for i in "${!AVAIL_LABELS[@]}"; do
            [[ "${AVAIL_LABELS[$i]}" != "$choice" ]] && continue
            mac="${AVAIL_MACS[$i]}"
            echo "trust $mac"   >&"${BTCTL[1]}"
            echo "pair $mac"    >&"${BTCTL[1]}"
            sleep 3
            echo "connect $mac" >&"${BTCTL[1]}"
            break 2
        done
    done
}

show_main_menu
