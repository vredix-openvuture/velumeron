#!/usr/bin/env bash
# Hyprland interactive configurator – writes device-specific settings
# to $VUTURELAND_USER_DIR/hypr.lua/user_settings.lua

set -euo pipefail

# Package source (read-only on AUR installs) and per-user state dir.
: "${VUTURELAND_DIR:=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)}"
: "${VUTURELAND_USER_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/vutureland}"

HYPR_DIR="$VUTURELAND_USER_DIR/hypr"
MODULES_DIR="$HYPR_DIR/modules"
USER_SETTINGS="$VUTURELAND_USER_DIR/hypr.lua/user_settings.lua"

mkdir -p "$HYPR_DIR" "$MODULES_DIR" "$VUTURELAND_USER_DIR/hypr.lua"

# ─── helpers ────────────────────────────────────────────────────────────────

say()  { echo -e "\n\033[1;34m$*\033[0m"; }
ok()   { echo -e "\033[1;32m✓ $*\033[0m"; }
warn() { echo -e "\033[1;33m! $*\033[0m"; }
hr()   { echo "────────────────────────────────────────────────────────────"; }

ask() {
    local prompt="$1" default="${2:-}"
    local label="$prompt"
    [[ -n "$default" ]] && label="$prompt [$default]"
    read -rp "  $label: " val
    echo "${val:-$default}"
}

ask_yn() {
    local prompt="$1" default="${2:-n}"
    read -rp "  $prompt [y/n] (${default}): " ans
    ans="${ans:-$default}"
    [[ "$ans" =~ ^[Yy] ]]
}

read_lua_var() {
    local file="$1" key="$2"
    # Try quoted string: key = "value"
    local val
    val=$(grep -m1 "^${key}[[:space:]]*=" "$file" 2>/dev/null | grep -oP '=\s*"\K[^"]*' | head -1 || true)
    if [[ -z "$val" ]]; then
        # Try unquoted value: key = 42
        val=$(grep -m1 "^${key}[[:space:]]*=" "$file" 2>/dev/null | sed 's/[^=]*=[[:space:]]*//' | sed 's/[[:space:]]*--.*$//' | tr -d '"' | xargs || true)
    fi
    echo "$val"
}

# Writes stdin content into the named section of user_settings.lua.
# Markers: -- <<<SECTIONNAME-START>>> / -- <<<SECTIONNAME-END>>>
write_section() {
    local section="$1"
    local new_content; new_content="$(cat)"
    local start="-- <<<${section}-START>>>"
    local end="-- <<<${section}-END>>>"

    if [[ ! -f "$USER_SETTINGS" ]]; then
        warn "user_settings.lua not found – please run a full configuration first."
        return 1
    fi

    if grep -qF -- "$start" "$USER_SETTINGS"; then
        local tmp; tmp=$(mktemp)
        local skip=0
        while IFS= read -r line; do
            if [[ "$line" == "$start" ]]; then
                printf '%s\n' "$line"
                printf '%s\n' "$new_content"
                skip=1
            elif [[ "$line" == "$end" ]]; then
                printf '%s\n' "$line"
                skip=0
            elif [[ $skip -eq 0 ]]; then
                printf '%s\n' "$line"
            fi
        done < "$USER_SETTINGS" > "$tmp"
        mv "$tmp" "$USER_SETTINGS"
    else
        warn "Section $section not found in user_settings.lua."
        return 1
    fi
}

# Prints only the lines within a named section.
read_section() {
    local section="$1"
    local start="-- <<<${section}-START>>>"
    local end="-- <<<${section}-END>>>"
    local in_section=0
    while IFS= read -r line; do
        [[ "$line" == "$start" ]] && in_section=1 && continue
        [[ "$line" == "$end" ]]   && in_section=0 && continue
        [[ $in_section -eq 1 ]] && printf '%s\n' "$line"
    done < "$USER_SETTINGS"
}

# ─── 1) Monitors ────────────────────────────────────────────────────────────

_mon_field() {
    local output="$1" field="$2" fallback="$3"
    local val
    val=$(awk "
        /hl\\.monitor\\(\\{/ { in_block=1; match_block=0 }
        in_block && /output[[:space:]]*=[[:space:]]*\"$output\"/ { match_block=1 }
        in_block && match_block && /${field}[[:space:]]*=/ {
            gsub(/.*=[[:space:]]*/, \"\")
            gsub(/,.*/, \"\")
            gsub(/[[:space:]]/, \"\")
            gsub(/\"/, \"\")
            print; exit
        }
        /^\\}\\)/ { in_block=0; match_block=0 }
    " "$USER_SETTINGS" 2>/dev/null | head -1 || true)
    echo "${val:-$fallback}"
}

_pick_from_list() {
    local prompt="$1" default="$2"; shift 2
    local -a items=("$@")
    echo ""
    for i in "${!items[@]}"; do
        local marker="  "
        [[ "${items[$i]}" == "$default" ]] && marker="► "
        printf "  %s%2d) %s\n" "$marker" "$((i+1))" "${items[$i]}"
    done
    echo ""
    read -rp "  $prompt [${default}]: " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#items[@]} )); then
        PICK_RESULT="${items[$((sel-1))]}"
    else
        PICK_RESULT="${sel:-$default}"
    fi
}

configure_monitors() {
    say "── MONITORS ──────────────────────────────────────────────────"

    local monitors_json="[]"
    if command -v hyprctl &>/dev/null; then
        monitors_json=$(hyprctl monitors -j 2>/dev/null || echo "[]")
    fi

    local -a detected_names=()
    mapfile -t detected_names < <(echo "$monitors_json" | jq -r '.[].name' 2>/dev/null || true)

    local cur_mon1 cur_mon2
    cur_mon1=$(read_lua_var "$USER_SETTINGS" "mon1")
    cur_mon2=$(read_lua_var "$USER_SETTINGS" "mon2")

    say "  Monitor 1 (primary)"
    if [[ ${#detected_names[@]} -gt 0 ]]; then
        _pick_from_list "Monitor 1 – number or name" "${cur_mon1:-${detected_names[0]}}" "${detected_names[@]}"
        local mon1="$PICK_RESULT"
    else
        warn "hyprctl not available – enter names manually."
        local mon1; mon1=$(ask "  Monitor 1" "${cur_mon1:-DP-2}")
    fi

    say "  Monitor 2 (secondary)"
    local mon2=""
    if [[ ${#detected_names[@]} -gt 0 ]]; then
        local -a mon2_opts=("(none)" "${detected_names[@]}")
        _pick_from_list "Monitor 2 – number or name" "${cur_mon2:-(none)}" "${mon2_opts[@]}"
        [[ "$PICK_RESULT" != "(none)" ]] && mon2="$PICK_RESULT"
    else
        mon2=$(ask "  Monitor 2 (empty = none)" "${cur_mon2:-}")
    fi

    _configure_one_monitor "$mon1" "1" "0x0" "0" "$monitors_json"
    local m1_mode="$CFG_MODE" m1_pos="$CFG_POS" m1_transform="$CFG_TRANSFORM" \
          m1_scale="$CFG_SCALE" m1_hdr="$CFG_HDR" m1_vrr="$CFG_VRR"

    local m2_mode="" m2_pos="" m2_transform="" m2_scale="" m2_hdr="" m2_vrr=""
    if [[ -n "$mon2" ]]; then
        _configure_one_monitor "$mon2" "2" "auto" "3" "$monitors_json"
        m2_mode="$CFG_MODE" m2_pos="$CFG_POS" m2_transform="$CFG_TRANSFORM"
        m2_scale="$CFG_SCALE" m2_hdr="$CFG_HDR" m2_vrr="$CFG_VRR"
    fi

    {
        printf 'mon1 = "%s"\n' "$mon1"
        [[ -n "$mon2" ]] && printf 'mon2 = "%s"\n' "$mon2"
        printf '\nhl.monitor({\n'
        printf '    output       = "%s",\n    mode         = "%s",\n    transform    = %s,\n' "$mon1" "$m1_mode" "$m1_transform"
        printf '    position     = "%s",\n    scale        = %s,\n    bitdepth     = 10,\n' "$m1_pos" "$m1_scale"
        printf '    supports_hdr = %s,\n    vrr          = %s,\n    cm           = "auto",\n})\n' \
            "$([ "$m1_hdr" = "1" ] && echo "true" || echo "false")" \
            "$([ "$m1_vrr" = "on" ] && echo "1" || echo "0")"
        if [[ -n "$mon2" ]]; then
            printf '\nhl.monitor({\n'
            printf '    output       = "%s",\n    mode         = "%s",\n    transform    = %s,\n' "$mon2" "$m2_mode" "$m2_transform"
            printf '    position     = "%s",\n    scale        = %s,\n    bitdepth     = 10,\n' "$m2_pos" "$m2_scale"
            printf '    supports_hdr = %s,\n    vrr          = %s,\n    cm           = "auto",\n})\n' \
                "$([ "$m2_hdr" = "1" ] && echo "true" || echo "false")" \
                "$([ "$m2_vrr" = "on" ] && echo "1" || echo "0")"
        fi
    } | write_section "MONITORS"

    ok "Monitors saved."
}

_configure_one_monitor() {
    local output="$1" num="$2" default_pos="$3" default_transform="$4" monitors_json="$5"

    say "  ── Monitor $num: $output"

    local -a modes=()
    mapfile -t modes < <(
        echo "$monitors_json" | jq -r --arg n "$output" \
        '.[] | select(.name==$n) | .availableModes[]' 2>/dev/null | \
        sed 's/Hz$//' | sort -t@ -k2 -rn || true
    )

    local cur_mode; cur_mode=$(_mon_field "$output" "mode" "2560x1440@165")
    if [[ ${#modes[@]} -gt 0 ]]; then
        say "  Resolution / Refresh Rate:"
        _pick_from_list "Number or custom value" "$cur_mode" "${modes[@]}"
        CFG_MODE="$PICK_RESULT"
    else
        CFG_MODE=$(ask "  Resolution@Hz" "$cur_mode")
    fi

    local -a transforms=(
        "0  –  0°   (normal)"          "1  –  90°  (clockwise)"
        "2  –  180°"                    "3  –  270° (clockwise)"
        "4  –  0°   (mirrored)"        "5  –  90°  (mirrored)"
        "6  –  180° (mirrored)"        "7  –  270° (mirrored)"
    )
    local cur_transform; cur_transform=$(_mon_field "$output" "transform" "$default_transform")
    say "  Transform:"
    _pick_from_list "Number" "${transforms[$cur_transform]:-$cur_transform}" "${transforms[@]}"
    CFG_TRANSFORM="${PICK_RESULT:0:1}"

    local cur_scale; cur_scale=$(_mon_field "$output" "scale" "1")
    local -a scales=("1" "1.25" "1.5" "1.75" "2")
    say "  Scale:"
    _pick_from_list "Number or custom value" "$cur_scale" "${scales[@]}"
    CFG_SCALE="$PICK_RESULT"

    local cur_pos; cur_pos=$(_mon_field "$output" "position" "$default_pos")
    CFG_POS=$(ask "  Position (XxY)" "$cur_pos")  # e.g. 0x0 or auto

    local cur_hdr; cur_hdr=$(_mon_field "$output" "supports_hdr" "false")
    ask_yn "  Enable HDR?" "$([ "$cur_hdr" = "true" ] && echo y || echo n)" && CFG_HDR=1 || CFG_HDR=0

    local cur_vrr; cur_vrr=$(_mon_field "$output" "vrr" "0")
    ask_yn "  Enable VRR?" "$([ "$cur_vrr" = "1" ] && echo y || echo n)" && CFG_VRR=on || CFG_VRR=off
}

# ─── 2) Workspaces ──────────────────────────────────────────────────────────

g_WS_NUM=(); g_WS_MON=(); g_WS_PERSIST=(); g_WS_DEFAULT=()

_ws_load() {
    g_WS_NUM=(); g_WS_MON=(); g_WS_PERSIST=(); g_WS_DEFAULT=()
    while IFS= read -r line; do
        [[ "$line" =~ hl\.workspace_rule ]] || continue
        local num mon persist def
        num=$(echo "$line"     | grep -oP 'workspace\s*=\s*"\K[^"]*')
        mon=$(echo "$line"     | grep -oP 'monitor\s*=\s*\K[^,}]+' | tr -d ' ')
        persist=$(echo "$line" | grep -oP 'persistent\s*=\s*\K(true|false)')
        echo "$line" | grep -q 'default\s*=\s*true' && def="true" || def="false"
        [[ -z "$num" || -z "$mon" ]] && continue
        g_WS_NUM+=("$num"); g_WS_MON+=("$mon")
        g_WS_PERSIST+=("${persist:-false}"); g_WS_DEFAULT+=("$def")
    done < <(read_section "WORKSPACES")
}

_ws_sorted_idx_for_mon() {
    local mon_var="$1"; local -a raw=()
    for i in "${!g_WS_NUM[@]}"; do
        [[ "${g_WS_MON[$i]}" == "$mon_var" ]] && raw+=("$(printf '%09d %d' "${g_WS_NUM[$i]}" "$i")")
    done
    IFS=$'\n' raw=($(printf '%s\n' "${raw[@]}" | sort -n)); unset IFS
    for entry in "${raw[@]}"; do echo "${entry##* }"; done
}

_ws_show_list() {
    local mon_var="$1" mon_name="$2"
    local -a idx=(); mapfile -t idx < <(_ws_sorted_idx_for_mon "$mon_var")
    echo ""; say "  $mon_var  ($mon_name)"; hr
    if [[ ${#idx[@]} -eq 0 ]]; then
        echo "  (no workspaces assigned)"
    else
        printf "  %-8s  %-12s  %s\n" "No." "Persistent" "Default"; hr
        for i in "${idx[@]}"; do
            local def_mark="  "
            [[ "${g_WS_DEFAULT[$i]}" == "true" ]] && def_mark="★ "
            printf "  %-8s  %-12s  %s\n" "${g_WS_NUM[$i]}" "${g_WS_PERSIST[$i]}" "$def_mark"
        done
    fi
}

_ws_submenu() {
    local mon_var="$1" mon_name="$2"
    while true; do
        _ws_show_list "$mon_var" "$mon_name"
        echo ""; echo "  a) Add  p) Persistent  d) Remove  q) Back"; hr
        read -rp "  Selection: " choice
        case "$choice" in
            a)
                local new_num; new_num=$(ask "  Workspace number")
                [[ -z "$new_num" || ! "$new_num" =~ ^[0-9]+$ ]] && warn "Invalid number." && continue
                local already=false
                for i in "${!g_WS_NUM[@]}"; do [[ "${g_WS_NUM[$i]}" == "$new_num" ]] && already=true && break; done
                $already && warn "Workspace $new_num already assigned." && continue
                local p="false" df="false"
                ask_yn "  Persistent?" "y" && p="true"
                ask_yn "  Set as default?" "n" && df="true"
                g_WS_NUM+=("$new_num"); g_WS_MON+=("$mon_var")
                g_WS_PERSIST+=("$p"); g_WS_DEFAULT+=("$df")
                ok "Workspace $new_num added."
                ;;
            p)
                read -rp "  Workspace number: " n; local found=false
                for i in "${!g_WS_NUM[@]}"; do
                    if [[ "${g_WS_NUM[$i]}" == "$n" && "${g_WS_MON[$i]}" == "$mon_var" ]]; then
                        [[ "${g_WS_PERSIST[$i]}" == "true" ]] && g_WS_PERSIST[$i]="false" || g_WS_PERSIST[$i]="true"
                        ok "Workspace $n: persistent=${g_WS_PERSIST[$i]}"; found=true; break
                    fi
                done
                $found || warn "Workspace $n not found."
                ;;
            d)
                read -rp "  Workspace number to remove: " n
                local -a nnum=() nmon=() npers=() ndef=(); local removed=false
                for i in "${!g_WS_NUM[@]}"; do
                    if [[ "${g_WS_NUM[$i]}" == "$n" && "${g_WS_MON[$i]}" == "$mon_var" ]]; then
                        removed=true; continue
                    fi
                    nnum+=("${g_WS_NUM[$i]}"); nmon+=("${g_WS_MON[$i]}")
                    npers+=("${g_WS_PERSIST[$i]}"); ndef+=("${g_WS_DEFAULT[$i]}")
                done
                g_WS_NUM=("${nnum[@]+"${nnum[@]}"}"); g_WS_MON=("${nmon[@]+"${nmon[@]}"}")
                g_WS_PERSIST=("${npers[@]+"${npers[@]}"}"); g_WS_DEFAULT=("${ndef[@]+"${ndef[@]}"}")
                $removed && ok "Workspace $n removed." || warn "Workspace $n not found."
                ;;
            q) break ;;
            *) warn "Invalid selection." ;;
        esac
    done
}

_ws_write() {
    local -a sorted=()
    mapfile -t sorted < <(
        for i in "${!g_WS_NUM[@]}"; do printf '%09d %d\n' "${g_WS_NUM[$i]}" "$i"; done \
        | sort -n | awk '{print $2}'
    )
    {
        local prev_mon=""
        for i in "${sorted[@]}"; do
            local mon="${g_WS_MON[$i]}"
            if [[ "$mon" != "$prev_mon" ]]; then
                [[ -n "$prev_mon" ]] && echo ""
                echo "-- $mon"; prev_mon="$mon"
            fi
            local line="hl.workspace_rule({ workspace = \"${g_WS_NUM[$i]}\","
            line+=" monitor = ${g_WS_MON[$i]}, persistent = ${g_WS_PERSIST[$i]}"
            [[ "${g_WS_DEFAULT[$i]}" == "true" ]] && line+=", default = true"
            line+=" })"
            echo "$line"
        done
    } | write_section "WORKSPACES"
}

configure_workspaces() {
    say "── WORKSPACES ────────────────────────────────────────────────"
    local -a MON_VARS=() MON_NAMES=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^mon([0-9]+)[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
            MON_VARS+=("mon${BASH_REMATCH[1]}")
            MON_NAMES+=("${BASH_REMATCH[2]}")
        fi
    done < <(read_section "MONITORS") 2>/dev/null || true

    if [[ ${#MON_VARS[@]} -eq 0 ]]; then
        warn "Configure monitors first (option 1)."; return
    fi

    _ws_load

    while true; do
        echo ""; hr; echo "  Select monitor:"; echo ""
        for i in "${!MON_VARS[@]}"; do
            local count=0
            for m in "${g_WS_MON[@]+"${g_WS_MON[@]}"}"; do
                [[ "$m" == "${MON_VARS[$i]}" ]] && (( count++ )) || true
            done
            printf "  %d) %s  (%s)  – %d Workspace(s)\n" "$((i+1))" "${MON_VARS[$i]}" "${MON_NAMES[$i]}" "$count"
        done
        echo ""; echo "  q) Save & back"; hr
        read -rp "  Selection: " sel
        if [[ "$sel" == "q" ]]; then
            _ws_write; ok "Workspaces saved."; break
        fi
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#MON_VARS[@]} )); then
            _ws_submenu "${MON_VARS[$((sel-1))]}" "${MON_NAMES[$((sel-1))]}"
        else
            warn "Invalid selection."
        fi
    done
}

# ─── 3) Autostart ───────────────────────────────────────────────────────────

configure_autostart() {
    say "── AUTOSTART ─────────────────────────────────────────────────"
    local -a daemons=() start_apps=() start_ws=()

    # Read exec_once_daemons table
    local in_daemons=0
    while IFS= read -r line; do
        if [[ "$line" =~ exec_once_daemons[[:space:]]*= ]]; then
            in_daemons=1; continue
        fi
        if [[ $in_daemons -eq 1 ]]; then
            [[ "$line" =~ ^[[:space:]]*\} ]] && break
            if [[ "$line" =~ \"([^\"]+)\" ]]; then
                daemons+=("${BASH_REMATCH[1]}")
            fi
        fi
    done < <(read_section "AUTOSTART")

    # Read start_apps table
    local in_apps=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^start_apps[[:space:]]*= ]]; then
            in_apps=1; continue
        fi
        if [[ $in_apps -eq 1 ]]; then
            [[ "$line" =~ ^\} ]] && break
            if [[ "$line" =~ \{[[:space:]]*app[[:space:]]*=[[:space:]]*\"([^\"]*)\".*ws[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
                local idx="${#start_apps[@]}"
                start_apps[$idx]="${BASH_REMATCH[1]}"
                start_ws[$idx]="${BASH_REMATCH[2]}"
            fi
        fi
    done < <(read_section "AUTOSTART")

    for i in $(seq 0 9); do
        start_apps[$i]="${start_apps[$i]:-}"
        start_ws[$i]="${start_ws[$i]:-$((i+1))}"
    done

    while true; do
        echo ""; hr
        echo "  a) Manage autostart commands"
        echo "  b) Manage workspace startup apps"
        echo "  q) Back"; hr
        read -rp "  Selection: " choice
        case "$choice" in
            a) manage_daemon_list daemons ;;
            b) manage_workspace_apps start_apps start_ws ;;
            q) break ;;
            *) warn "Invalid selection." ;;
        esac
    done

    {
        echo "exec_once_daemons = {"
        for d in "${daemons[@]}"; do
            printf '    "%s",\n' "$d"
        done
        echo "}"
        echo ""
        echo "-- { app = command, ws = workspace_number }"
        echo "start_apps = {"
        for i in "${!start_apps[@]}"; do
            printf '    { app = "%s", ws = %s },\n' "${start_apps[$i]}" "${start_ws[$i]:-$((i+1))}"
        done
        echo "}"
    } | write_section "AUTOSTART"

    ok "Autostart saved."
}

manage_daemon_list() {
    local -n _list=$1
    while true; do
        echo ""; echo "  Current entries:"
        [[ ${#_list[@]} -eq 0 ]] && echo "    (empty)" || \
            for i in "${!_list[@]}"; do printf "    %2d) %s\n" "$((i+1))" "${_list[$i]}"; done
        echo ""; echo "  a) Add   d) Delete   q) Back"
        read -rp "  Selection: " c
        case "$c" in
            a) local cmd; cmd=$(ask "  Command"); [[ -n "$cmd" ]] && _list+=("$cmd") ;;
            d) read -rp "  Number: " n
               [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#_list[@]} )) && \
               _list=("${_list[@]:0:$((n-1))}" "${_list[@]:$n}") ;;
            q) break ;;
        esac
    done
}

manage_workspace_apps() {
    local -n _apps=$1; local -n _ws=$2
    while true; do
        echo ""; echo "  Slot   Workspace   Command"
        for i in "${!_apps[@]}"; do
            printf "    %2d)    %-6s    %s\n" "$((i+1))" "${_ws[$i]:-}" "${_apps[$i]:-(empty)}"
        done
        echo ""; echo "  Slot number to edit, q = Back"
        read -rp "  Selection: " sel
        [[ "$sel" == "q" ]] && break
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#_apps[@]} )); then
            local idx=$((sel-1))
            _apps[$idx]=$(ask "  Command (empty = disabled)" "${_apps[$idx]:-}")
            _ws[$idx]=$(ask "  Workspace" "${_ws[$idx]:-$sel}")
        fi
    done
}

# ─── 4) Quick Access ────────────────────────────────────────────────────────

configure_quickaccess() {
    say "── QUICK ACCESS ──────────────────────────────────────────────"
    echo ""; echo "  Define up to 10 apps for the quickstart submap."; echo ""

    local -a apps=()
    for i in $(seq 1 10); do apps+=(""); done

    # Read quick_app table
    local in_qa=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^quick_app[[:space:]]*= ]]; then
            in_qa=1; continue
        fi
        if [[ $in_qa -eq 1 ]]; then
            [[ "$line" =~ ^\} ]] && break
            if [[ "$line" =~ \[([0-9]+)\][[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
                local idx=$((${BASH_REMATCH[1]}-1))
                apps[$idx]="${BASH_REMATCH[2]}"
            fi
        fi
    done < <(read_section "QUICKACCESS")

    for i in "${!apps[@]}"; do
        apps[$i]=$(ask "  App $((i+1))" "${apps[$i]:-}")
    done

    {
        echo "quick_app = {"
        for i in "${!apps[@]}"; do
            printf '    [%-2d] = "%s",\n' "$((i+1))" "${apps[$i]}"
        done
        echo "}"
    } | write_section "QUICKACCESS"

    ok "Quick Access saved."
}

# ─── 5) Peripherals ─────────────────────────────────────────────────────────

configure_peripherals() {
    say "── PERIPHERALS ───────────────────────────────────────────────"

    local cur_theme cur_size
    cur_theme=$(read_lua_var "$USER_SETTINGS" "cur_theme")
    cur_size=$(read_lua_var  "$USER_SETTINGS" "cur_size")

    echo ""; echo "  Available cursor themes:"
    local themes=()
    mapfile -t themes < <(find /usr/share/icons -maxdepth 2 -name "cursors" -type d \
        2>/dev/null | sed 's|/usr/share/icons/||;s|/cursors||' | sort)

    if [[ ${#themes[@]} -gt 0 ]]; then
        for i in "${!themes[@]}"; do printf "    %2d) %s\n" "$((i+1))" "${themes[$i]}"; done
        echo ""; read -rp "  Number or custom name [${cur_theme:-Oxygen}]: " sel
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#themes[@]} )); then
            cur_theme="${themes[$((sel-1))]}"
        else
            cur_theme="${sel:-${cur_theme:-Oxygen}}"
        fi
    else
        cur_theme=$(ask "  Cursor theme" "${cur_theme:-Oxygen}")
    fi
    cur_size=$(ask "  Cursor size" "${cur_size:-24}")

    echo ""; say "  FN keys:"
    local fn_bup fn_bdn fn_play fn_next fn_prev fn_vup fn_vdn fn_mute
    fn_bup=$(read_lua_var  "$USER_SETTINGS" "fn_brightness_up")
    fn_bdn=$(read_lua_var  "$USER_SETTINGS" "fn_brightness_down")
    fn_play=$(read_lua_var "$USER_SETTINGS" "fn_play_stop_play")
    fn_next=$(read_lua_var "$USER_SETTINGS" "fn_play_next")
    fn_prev=$(read_lua_var "$USER_SETTINGS" "fn_play_prev")
    fn_vup=$(read_lua_var  "$USER_SETTINGS" "fn_volume_up")
    fn_vdn=$(read_lua_var  "$USER_SETTINGS" "fn_volume_down")
    fn_mute=$(read_lua_var "$USER_SETTINGS" "fn_volume_mute")

    fn_bup=$(ask  "  Brightness up    " "${fn_bup:-F2}")
    fn_bdn=$(ask  "  Brightness down  " "${fn_bdn:-F1}")
    fn_play=$(ask "  Play/Pause       " "${fn_play:-F8}")
    fn_next=$(ask "  Next track       " "${fn_next:-F9}")
    fn_prev=$(ask "  Previous track   " "${fn_prev:-F7}")
    fn_vup=$(ask  "  Volume up        " "${fn_vup:-F12}")
    fn_vdn=$(ask  "  Volume down      " "${fn_vdn:-F11}")
    fn_mute=$(ask "  Mute             " "${fn_mute:-F10}")

    {
        echo "cur_theme = \"$cur_theme\""
        echo "cur_size  = $cur_size"
        echo ""
        echo "fn_brightness_up   = \"$fn_bup\""
        echo "fn_brightness_down = \"$fn_bdn\""
        echo "fn_play_stop_play  = \"$fn_play\""
        echo "fn_play_next       = \"$fn_next\""
        echo "fn_play_prev       = \"$fn_prev\""
        echo "fn_volume_up       = \"$fn_vup\""
        echo "fn_volume_down     = \"$fn_vdn\""
        echo "fn_volume_mute     = \"$fn_mute\""
    } | write_section "PERIPHERALS"

    ok "Peripherals saved."
}

# ─── 6) Window Rules ────────────────────────────────────────────────────────

configure_windowrules() {
    say "── WINDOW RULES ──────────────────────────────────────────────"

    local float_rule opacity_rule
    float_rule=$(read_lua_var  "$USER_SETTINGS" "floating_window")
    opacity_rule=$(read_lua_var "$USER_SETTINGS" "opacity_window")

    echo ""; echo "  Regex patterns (separate multiple with |: .*kitty.*|.*ark.*)"; echo ""
    float_rule=$(ask   "  floating_window" "${float_rule:-(.*kitty.*|.*ark.*|.*bitwarden.*)}")
    opacity_rule=$(ask "  opacity_window " "${opacity_rule:-(.*obsidian.*)}")

    {
        echo "floating_window = \"$float_rule\""
        echo "opacity_window  = \"$opacity_rule\""
    } | write_section "WINDOWRULES"

    ok "Window rules saved."
}

# ─── Save & reload ──────────────────────────────────────────────────────────

save_and_reload() {
    say "── SAVE & RELOAD ─────────────────────────────────────────────"
    echo ""; echo "  Reloading configuration…"
    if hyprctl reload 2>&1; then
        ok "Hyprland reloaded successfully."
    else
        warn "hyprctl reload failed – is Hyprland running?"
    fi
}

# ─── Bootstrap: create skeleton user_settings.lua if missing ────────────────

init_user_settings() {
    # Symlink ~/.config/wallust → vutureland/wallust so wallust always finds its config
    if [[ ! -e "$HOME/.config/wallust" ]]; then
        ln -sf "$VUTURELAND_DIR/wallust" "$HOME/.config/wallust"
        ok "Linked ~/.config/wallust → vutureland/wallust"
    fi

    if [[ -f "$USER_SETTINGS" ]]; then
        # Check for section markers — required for write_section to work
        if ! grep -qF -- '-- <<<MONITORS-START>>>' "$USER_SETTINGS"; then
            warn "user_settings.lua exists but has no section markers."
            warn "hyprland.sh cannot manage it without -- <<<SECTION-START>>> / -- <<<SECTION-END>>> markers."
            echo ""
            echo "  Options:"
            echo "    r) Regenerate from scratch (current values will be lost)"
            echo "    q) Exit and add markers manually"
            echo ""
            read -rp "  Selection [q]: " sel
            case "${sel:-q}" in
                r)
                    rm -f "$USER_SETTINGS"
                    ok "Removed old file. Generating new skeleton…"
                    ;;
                *)
                    echo ""
                    echo "  Add these markers around each section in $USER_SETTINGS:"
                    echo "    -- <<<MONITORS-START>>>   / -- <<<MONITORS-END>>>"
                    echo "    -- <<<WORKSPACES-START>>> / -- <<<WORKSPACES-END>>>"
                    echo "    -- <<<PERIPHERALS-START>>>/ -- <<<PERIPHERALS-END>>>"
                    echo "    -- <<<QUICKACCESS-START>>>/ -- <<<QUICKACCESS-END>>>"
                    echo "    -- <<<AUTOSTART-START>>>  / -- <<<AUTOSTART-END>>>"
                    echo "    -- <<<WINDOWRULES-START>>>/ -- <<<WINDOWRULES-END>>>"
                    echo ""
                    exit 0
                    ;;
            esac
        else
            return
        fi
    fi

    mkdir -p "$VUTURELAND_USER_DIR/hypr.lua"
    cat > "$USER_SETTINGS" <<'EOF'
-- ════════════════════════════════════════════════════════════════════════
--
--  USER SETTINGS — Device-specific settings.
--  Generated by hyprland.sh. Not in git. Do not edit manually.
--
-- ════════════════════════════════════════════════════════════════════════


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  MONITORS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<MONITORS-START>>>
-- <<<MONITORS-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  WORKSPACES
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<WORKSPACES-START>>>
-- <<<WORKSPACES-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  PERIPHERALS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<PERIPHERALS-START>>>
cur_theme = "Oxygen"
cur_size  = 24

fn_brightness_up   = "F2"
fn_brightness_down = "F1"
fn_play_stop_play  = "F8"
fn_play_next       = "F9"
fn_play_prev       = "F7"
fn_volume_up       = "F12"
fn_volume_down     = "F11"
fn_volume_mute     = "F10"
-- <<<PERIPHERALS-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  QUICK ACCESS APPS  (index = key number)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<QUICKACCESS-START>>>
quick_app = {
    [1]  = "",
    [2]  = "",
    [3]  = "",
    [4]  = "",
    [5]  = "",
    [6]  = "",
    [7]  = "",
    [8]  = "",
    [9]  = "",
    [10] = "",
    [11] = "",
    [12] = "",
}
-- <<<QUICKACCESS-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  AUTOSTART — Device daemons & workspace startup apps
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<AUTOSTART-START>>>
exec_once_daemons = {
}

-- { app = command, ws = workspace_number }
start_apps = {
    { app = "", ws = 1 },
    { app = "", ws = 2 },
    { app = "", ws = 3 },
    { app = "", ws = 4 },
    { app = "", ws = 5 },
    { app = "", ws = 6 },
    { app = "", ws = 7 },
    { app = "", ws = 8 },
    { app = "", ws = 9 },
    { app = "", ws = 10 },
}
-- <<<AUTOSTART-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  WINDOW RULE VARIABLES
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<WINDOWRULES-START>>>
floating_window = "(.*kitty.*|.*ark.*|.*bitwarden.*)"
opacity_window  = "(.*obsidian.*)"
-- <<<WINDOWRULES-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Look and Feel — overrides for hypr.lua defaults. Leave a value unset
-- (commented / absent) to fall back to the default in look_and_feel.lua.
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<LOOKANDFEEL-START>>>
-- <<<LOOKANDFEEL-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  ROLE APPS & SYSTEM COMMANDS — set per device, not in git.
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<ROLEAPPS-START>>>
filemanager      = ""
messenger        = ""
player           = ""
notes_app        = ""
clock_app        = ""
mail_app         = ""
calendar_app     = ""
tasks_app        = ""
editor_app       = ""
wifi_menu        = ""
bluetooth_menu   = ""
vpn_toggle       = ""
audio_switch     = ""
mic_mute         = "pactl set-source-mute @DEFAULT_SOURCE@ toggle"
night_light      = ""
dnd_toggle       = "swaync-client --toggle-dnd"
screen_record    = ""
bitwarden        = "bitwarden"
-- <<<ROLEAPPS-END>>>
EOF
    ok "Created new user_settings.lua"
}

# ─── Non-interactive autostart configuration (--autostart) ──────────────────

autostart_config() {
    echo ""
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║   VUTURELAND – Autostart Configuration    ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo ""

    init_user_settings

    # ── 1) Monitors ──────────────────────────────────────────────────────────
    say "── MONITORS ──"

    local monitors_json
    monitors_json=$(hyprctl monitors -j 2>/dev/null || echo "[]")

    # Primary: focused monitor, else first detected
    local mon1
    mon1=$(echo "$monitors_json" | jq -r \
        'first(.[] | select(.focused==true) | .name) // .[0].name' 2>/dev/null || true)

    if [[ -z "$mon1" ]]; then
        warn "No monitors detected via hyprctl. Cannot continue."
        exit 1
    fi

    # Best mode: sort by pixel count (w×h) desc, then by refresh rate desc
    local best_mode
    best_mode=$(echo "$monitors_json" | \
        jq -r --arg n "$mon1" '.[] | select(.name==$n) | .availableModes[]' 2>/dev/null | \
        sed 's/Hz$//' | \
        awk -F'[@x]' '{ printf "%012.0f %010.3f %s\n", $1*$2, $3+0, $0 }' | \
        sort -rn | head -1 | awk '{print $3}' || true)

    # Fallback: use current active mode
    if [[ -z "$best_mode" ]]; then
        best_mode=$(echo "$monitors_json" | \
            jq -r --arg n "$mon1" \
            '.[] | select(.name==$n) | "\(.width)x\(.height)@\(.refreshRate | floor)"' \
            2>/dev/null || true)
        best_mode="${best_mode:-2560x1440@60}"
    fi

    ok "Monitor : $mon1"
    ok "Mode    : $best_mode"

    {
        printf 'mon1 = "%s"\n\n' "$mon1"
        printf 'hl.monitor({\n'
        printf '    output       = "%s",\n' "$mon1"
        printf '    mode         = "%s",\n' "$best_mode"
        printf '    transform    = 0,\n'
        printf '    position     = "0x0",\n'
        printf '    scale        = 1,\n'
        printf '    bitdepth     = 10,\n'
        printf '    supports_hdr = false,\n'
        printf '    vrr          = 0,\n'
        printf '    cm           = "auto",\n'
        printf '})\n'
    } | write_section "MONITORS"

    # ── 2) Workspaces: 1–5 on primary monitor, persistent ────────────────────
    say "── WORKSPACES ──"

    {
        echo "-- mon1"
        for ws in 1 2 3 4 5; do
            if [[ "$ws" == "1" ]]; then
                echo "hl.workspace_rule({ workspace = \"$ws\", monitor = mon1, persistent = true, default = true })"
            else
                echo "hl.workspace_rule({ workspace = \"$ws\", monitor = mon1, persistent = true })"
            fi
        done
    } | write_section "WORKSPACES"

    ok "Workspaces 1–5 → mon1 ($mon1), persistent (ws 1 = default)"

    # ── 3) Autostart: empty ───────────────────────────────────────────────────
    say "── AUTOSTART ──"

    {
        echo "exec_once_daemons = {"
        echo "}"
        echo ""
        echo "-- { app = command, ws = workspace_number }"
        echo "start_apps = {"
        for i in $(seq 1 10); do
            printf '    { app = "", ws = %d },\n' "$i"
        done
        echo "}"
    } | write_section "AUTOSTART"

    ok "Autostart: empty"
    echo ""
    save_and_reload
}

# ─── Main menu ──────────────────────────────────────────────────────────────

main() {
    local minimal=false
    for arg in "$@"; do [[ "$arg" == "--minimal" ]] && minimal=true; done

    clear; echo ""
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║      VUTURELAND – Hyprland Setup          ║"
    echo "  ╚═══════════════════════════════════════════╝"

    init_user_settings

    if [[ "$minimal" == "true" ]]; then
        configure_monitors
        configure_workspaces
        save_and_reload
        return
    fi

    while true; do
        echo ""; hr
        echo "  1) Monitors        4) Quick Access"
        echo "  2) Workspaces      5) Peripherals"
        echo "  3) Autostart       6) Window Rules"
        echo ""; echo "  q) Save & Reload"; hr
        read -rp "  Selection: " choice
        case "$choice" in
            1) configure_monitors    ;;
            2) configure_workspaces  ;;
            3) configure_autostart   ;;
            4) configure_quickaccess ;;
            5) configure_peripherals ;;
            6) configure_windowrules ;;
            q) save_and_reload; break ;;
            *) warn "Invalid selection." ;;
        esac
    done
}

if [[ "${1:-}" == "--autostart" ]]; then
    autostart_config
else
    main "$@"
fi
