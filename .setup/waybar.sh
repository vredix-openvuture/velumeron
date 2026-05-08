#!/usr/bin/env bash
# Vutureland – Waybar Setup
#
#   waybar.sh              → Interactive setup
#   waybar.sh --rebuild    → Rebuild + start Waybar (no menu)
#   waybar.sh --rebuild --debug

set -euo pipefail

VUTURELAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAYBAR_DIR="$VUTURELAND_DIR/waybar-modular"
MODULES_DIR="$WAYBAR_DIR/modules"
BASE_DIR="$WAYBAR_DIR/base"
OUTPUT_DIR="$WAYBAR_DIR/output"
LAUNCH_SCRIPT="$VUTURELAND_DIR/assets/scripts/launch-waybar.sh"

DEBUG=false
for arg in "$@"; do [[ "$arg" == "--debug" ]] && DEBUG=true; done

BOLD=$'\033[1m'; CYAN=$'\033[0;36m'; GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'; DIM=$'\033[2m'; RED=$'\033[0;31m'; RST=$'\033[0m'

dbg() { $DEBUG && echo "  [dbg] $*" >&2 || true; }
err() { echo "${RED}[ERR]${RST} $*" >&2; }
ok()  { echo "  ${GREEN}✓${RST}  $*"; }

print_header() {
    clear
    echo ""
    echo "  ${BOLD}${CYAN}╔══════════════════════════════════════╗${RST}"
    echo "  ${BOLD}${CYAN}║     Vutureland – Waybar Setup        ║${RST}"
    echo "  ${BOLD}${CYAN}╚══════════════════════════════════════╝${RST}"
    echo ""
}

print_step() {
    echo "  ${BOLD}── $* ${RST}"
    echo ""
}

ask() { printf "  ${YELLOW}▶${RST}  $1 "; }

# ─── Module / Container laden ─────────────────────────────────────────────────
declare -a MOD_FOLDERS=() MOD_KEYS=() MOD_ALIASES=() MOD_SECTIONS=() MOD_IS_CON=() MOD_SPECIFICS=()
declare -A KEY_TO_FOLDER=() FOLDER_TO_KEY=()

load_all_modules() {
    MOD_FOLDERS=(); MOD_KEYS=(); MOD_ALIASES=(); MOD_SECTIONS=(); MOD_IS_CON=(); MOD_SPECIFICS=()
    KEY_TO_FOLDER=(); FOLDER_TO_KEY=()

    declare -A mod_data=() con_data=() folder_specific=()

    # Metadaten aller Ordner einlesen (key|alias)
    for dir in "$MODULES_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local folder; folder="$(basename "$dir")"
        if [[ -f "$dir/module.md" ]]; then
            local key alias_val specific_val
            key=$(grep '^name'  "$dir/module.md" | sed 's/name *= *"\(.*\)"/\1/'  | head -1)
            alias_val=$(grep '^alias' "$dir/module.md" | sed 's/alias *= *"\(.*\)"/\1/' | head -1)
            specific_val=$(grep '^specific ' "$dir/module.md" 2>/dev/null | sed 's/specific *= *"\(.*\)"/\1/' | head -1 || true)
            [[ -z "$key"       ]] && key="$folder"
            [[ -z "$alias_val" ]] && alias_val="$folder"
            mod_data["$folder"]="$key|$alias_val"
            folder_specific["$folder"]="$specific_val"
        elif [[ -f "$dir/container.md" ]]; then
            local key alias_val specific_val
            key=$(grep '^name'  "$dir/container.md" | sed 's/name *= *"\(.*\)"/\1/'  | head -1)
            alias_val=$(grep '^alias' "$dir/container.md" | sed 's/alias *= *"\(.*\)"/\1/' | head -1)
            specific_val=$(grep '^specific ' "$dir/container.md" 2>/dev/null | sed 's/specific *= *"\(.*\)"/\1/' | head -1 || true)
            [[ -z "$key"       ]] && key="group/$folder"
            [[ -z "$alias_val" ]] && alias_val="$folder"
            con_data["$folder"]="$key|$alias_val"
            folder_specific["$folder"]="$specific_val"
        fi
    done

    # Module in Reihenfolge aus modules.md, mit Section-Erkennung
    local -a mod_processed=()
    local current_section="" pending_section=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^#[[:space:]]*(.*) ]]; then
            pending_section="${BASH_REMATCH[1]}"
            continue
        fi
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        local folder="$line"
        [[ -z "${mod_data[$folder]:-}" ]] && continue
        local key="${mod_data[$folder]%%|*}" alias_val="${mod_data[$folder]##*|}"
        MOD_FOLDERS+=("$folder"); MOD_KEYS+=("$key"); MOD_ALIASES+=("$alias_val")
        MOD_SECTIONS+=("$pending_section"); MOD_IS_CON+=("false"); MOD_SPECIFICS+=("${folder_specific[$folder]:-}")
        KEY_TO_FOLDER["$key"]="$folder"; FOLDER_TO_KEY["$folder"]="$key"
        mod_processed+=("$folder")
        pending_section=""
    done < "$MODULES_DIR/modules.md"

    # Verbleibende Module (nicht in modules.md) unter eigener Section
    local first_extra=true
    for folder in $(echo "${!mod_data[@]}" | tr ' ' '\n' | sort); do
        local found=false
        for p in "${mod_processed[@]:-}"; do [[ "$p" == "$folder" ]] && found=true && break; done
        $found && continue
        local key="${mod_data[$folder]%%|*}" alias_val="${mod_data[$folder]##*|}"
        MOD_FOLDERS+=("$folder"); MOD_KEYS+=("$key"); MOD_ALIASES+=("$alias_val")
        if $first_extra; then
            MOD_SECTIONS+=("Weitere"); first_extra=false
        else
            MOD_SECTIONS+=("")
        fi
        MOD_IS_CON+=("false"); MOD_SPECIFICS+=("${folder_specific[$folder]:-}")
        KEY_TO_FOLDER["$key"]="$folder"; FOLDER_TO_KEY["$folder"]="$key"
    done

    # Container in Reihenfolge aus containers.md, mit Section-Erkennung
    local containers_md="$MODULES_DIR/containers.md"
    local -a con_ordered=() con_sections=()
    if [[ -f "$containers_md" ]]; then
        local con_pending=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^#[[:space:]]*(.*) ]]; then
                con_pending="${BASH_REMATCH[1]}"; continue
            fi
            [[ "$line" =~ ^[[:space:]]*$ ]] && continue
            for folder in "${!con_data[@]}"; do
                [[ "${folder}" == *"${line//-/_}"* || "${folder}" == *"${line//_/-}"* ]] || continue
                con_ordered+=("$folder"); con_sections+=("$con_pending")
                con_pending=""; break
            done
        done < "$containers_md"
    fi
    for folder in "${!con_data[@]}"; do
        local found=false
        for c in "${con_ordered[@]:-}"; do [[ "$c" == "$folder" ]] && found=true && break; done
        $found || { con_ordered+=("$folder"); con_sections+=(""); }
    done

    for i in "${!con_ordered[@]}"; do
        local folder="${con_ordered[$i]}"
        [[ -z "${con_data[$folder]:-}" ]] && continue
        local key="${con_data[$folder]%%|*}" alias_val="${con_data[$folder]##*|}"
        MOD_FOLDERS+=("$folder"); MOD_KEYS+=("$key"); MOD_ALIASES+=("$alias_val")
        MOD_SECTIONS+=("${con_sections[$i]:-}"); MOD_IS_CON+=("true"); MOD_SPECIFICS+=("${folder_specific[$folder]:-}")
        KEY_TO_FOLDER["$key"]="$folder"; FOLDER_TO_KEY["$folder"]="$key"
    done

    dbg "Geladen: ${#MOD_FOLDERS[@]} Module/Container"
}

# ─── Monitore erkennen ────────────────────────────────────────────────────────
detect_monitors() {
    hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null || true
}

# ─── Interaktiver State ───────────────────────────────────────────────────────
STATE="monitor"
MONITOR="" POSITION="" STYLE="" SLOT=""
declare -a CUR_LEFT=() CUR_CENTER=() CUR_RIGHT=()
LAST_LOADED=""

# Breadcrumb-Zeile
breadcrumb() {
    local out="  "
    [[ -n "$MONITOR"  ]] && out+="${BOLD}$MONITOR${RST}"
    [[ -n "$POSITION" ]] && out+=" ${DIM}→${RST} $POSITION"
    [[ -n "$STYLE"    ]] && out+=" ${DIM}→${RST} $STYLE"
    [[ -n "$SLOT"     ]] && out+=" ${DIM}→${RST} ${CYAN}$SLOT${RST}"
    echo "$out"
    echo ""
}

# Slot preview (truncated if needed)
fmt_slot() {
    local -n _arr="$1"
    if [[ ${#_arr[@]} -eq 0 ]]; then
        printf "%b" "${DIM}(empty)${RST}"
        return
    fi
    local joined="${_arr[*]}"
    [[ ${#joined} -gt 60 ]] && joined="${joined:0:57}..."
    printf "%b" "${DIM}${joined}${RST}"
}

# Available styles for a position (from *.config.json files in the base folder)
get_styles_for_position() {
    find "$BASE_DIR/base-${1}" -maxdepth 1 -name "*.config.json" 2>/dev/null \
        | sed 's|.*/||; s|\.config\.json$||' | sort
}

# Load existing slot configuration from groups.json
load_existing_slots() {
    local groups_file="$OUTPUT_DIR/$STYLE/$POSITION/$MONITOR/groups.json"
    CUR_LEFT=(); CUR_CENTER=(); CUR_RIGHT=()
    [[ -f "$groups_file" ]] || return 0
    while IFS= read -r k; do [[ -n "$k" ]] && CUR_LEFT+=("$k");   done \
        < <(jq -r '."group/left".modules[]?   // empty' "$groups_file" 2>/dev/null || true)
    while IFS= read -r k; do [[ -n "$k" ]] && CUR_CENTER+=("$k"); done \
        < <(jq -r '."group/center".modules[]? // empty' "$groups_file" 2>/dev/null || true)
    while IFS= read -r k; do [[ -n "$k" ]] && CUR_RIGHT+=("$k");  done \
        < <(jq -r '."group/right".modules[]?  // empty' "$groups_file" 2>/dev/null || true)
}

# Bar bauen + Waybar starten
do_build() {
    clear
    print_header
    echo ""
    build_bar "$MONITOR" "$POSITION" "$STYLE" \
        "${CUR_LEFT[@]:-}" "--center" "${CUR_CENTER[@]:-}" "--right" "${CUR_RIGHT[@]:-}"
    echo ""
    kill_and_start
}

# ─── Screen 1: Monitor ────────────────────────────────────────────────────────
screen_monitor() {
    local -a monitors=()
    while IFS= read -r m; do [[ -n "$m" ]] && monitors+=("$m"); done \
        < <(detect_monitors)

    while true; do
        print_header
        print_step "Select monitor"

        if [[ ${#monitors[@]} -eq 0 ]]; then
            echo "  ${RED}No monitors detected.${RST}"
            echo ""
            ask "Enter monitor name manually (or B to exit): "
            local input; read -r input
            case "$input" in
                B|b) exit 0 ;;
                '')  continue ;;
                *)   MONITOR="$input"; STATE="position"; return ;;
            esac
        fi

        local i=1
        for m in "${monitors[@]}"; do
            printf "  ${CYAN}%2d)${RST}  %s\n" "$i" "$m"
            i=$((i+1))
        done
        echo ""
        echo "  ${DIM}B) Exit${RST}"
        echo ""
        ask "Monitor: "
        local input; read -r input

        case "$input" in
            B|b) exit 0 ;;
            ''|*[!0-9]*) continue ;;
            *)
                local idx=$((input - 1))
                if (( idx >= 0 && idx < ${#monitors[@]} )); then
                    MONITOR="${monitors[$idx]}"
                    STATE="position"
                    return
                fi ;;
        esac
    done
}

# ─── Screen 2: Position ───────────────────────────────────────────────────────
screen_position() {
    local -a avail=()
    for p in top bottom left right; do
        [[ -d "$BASE_DIR/base-${p}" ]] && avail+=("$p")
    done

    while true; do
        print_header
        breadcrumb

        print_step "Position"
        local i=1
        for p in "${avail[@]}"; do
            printf "  ${CYAN}%2d)${RST}  %s\n" "$i" "$p"
            i=$((i+1))
        done
        echo ""
        echo "  ${DIM}B) Back${RST}"
        echo ""
        ask "Position: "
        local input; read -r input

        case "$input" in
            B|b) POSITION=""; STATE="monitor"; return ;;
            ''|*[!0-9]*) continue ;;
            *)
                local idx=$((input - 1))
                if (( idx >= 0 && idx < ${#avail[@]} )); then
                    POSITION="${avail[$idx]}"
                    STATE="style"
                    return
                fi ;;
        esac
    done
}

# ─── Screen 3: Style ──────────────────────────────────────────────────────────
screen_style() {
    local -a styles=()
    while IFS= read -r s; do [[ -n "$s" ]] && styles+=("$s"); done \
        < <(get_styles_for_position "$POSITION")

    while true; do
        print_header
        breadcrumb

        print_step "Style"

        if [[ ${#styles[@]} -eq 0 ]]; then
            err "No style files in $BASE_DIR/base-${POSITION}/"
            sleep 2; STYLE=""; STATE="position"; return
        fi

        local i=1
        for s in "${styles[@]}"; do
            printf "  ${CYAN}%2d)${RST}  %s\n" "$i" "$s"
            i=$((i+1))
        done
        echo ""
        echo "  ${DIM}B) Back${RST}"
        echo ""
        ask "Style: "
        local input; read -r input

        case "$input" in
            B|b) STYLE=""; STATE="position"; return ;;
            ''|*[!0-9]*) continue ;;
            *)
                local idx=$((input - 1))
                if (( idx >= 0 && idx < ${#styles[@]} )); then
                    STYLE="${styles[$idx]}"
                    STATE="slot"
                    return
                fi ;;
        esac
    done
}

# ─── Screen 4: Slot-Auswahl ───────────────────────────────────────────────────
screen_slot() {
    local combo="$MONITOR|$POSITION|$STYLE"
    if [[ "$LAST_LOADED" != "$combo" ]]; then
        load_existing_slots
        LAST_LOADED="$combo"
    fi

    while true; do
        print_header
        breadcrumb

        print_step "Edit slot"
        printf "  ${CYAN} 1)${RST}  Left    "
        fmt_slot CUR_LEFT;   echo ""
        printf "  ${CYAN} 2)${RST}  Center  "
        fmt_slot CUR_CENTER; echo ""
        printf "  ${CYAN} 3)${RST}  Right   "
        fmt_slot CUR_RIGHT;  echo ""
        echo ""
        echo "  ${DIM}B) Back  |  S) Save + build Waybar${RST}"
        echo ""
        ask "Slot (1/2/3) or S/B: "
        local input; read -r input

        case "$input" in
            B|b) STYLE=""; SLOT=""; STATE="style"; return ;;
            S|s) do_build; exit 0 ;;
            1)   SLOT="left";   STATE="modules"; return ;;
            2)   SLOT="center"; STATE="modules"; return ;;
            3)   SLOT="right";  STATE="modules"; return ;;
        esac
    done
}

# ─── Screen 5: Module selection ──────────────────────────────────────────────
screen_modules() {
    local -a editing=()
    case "$SLOT" in
        left)   editing=("${CUR_LEFT[@]:-}") ;;
        center) editing=("${CUR_CENTER[@]:-}") ;;
        right)  editing=("${CUR_RIGHT[@]:-}") ;;
    esac

    while true; do
        print_header
        breadcrumb

        # Current selection as a horizontal list
        echo "  ${BOLD}Selection:${RST}"
        if [[ ${#editing[@]} -eq 0 ]]; then
            echo "  ${DIM}(empty)${RST}"
        else
            local line="  "
            for s in "${editing[@]}"; do
                line+="${CYAN}${s}${RST}  "
            done
            echo -e "$line"
        fi
        echo ""

        # Module list with section separators, filtered by slot
        local -a visible_indices=()
        local i=1
        local last_section=""
        for ((idx=0; idx<${#MOD_FOLDERS[@]}; idx++)); do
            local section="${MOD_SECTIONS[$idx]}"
            local alias_val="${MOD_ALIASES[$idx]}"
            local is_con="${MOD_IS_CON[$idx]}"
            local specific="${MOD_SPECIFICS[$idx]}"

            # Slot filter: if specific is set, only show in the matching slot
            if [[ -n "$specific" && "$specific" != "$SLOT" ]]; then
                continue
            fi

            # Print section header only if at least one module follows
            if [[ -n "$section" && "$section" != "$last_section" ]]; then
                echo ""
                printf "  ${BOLD}${DIM}── %s ${RST}\n" "$section"
                last_section="$section"
            fi

            if [[ "$is_con" == "true" ]]; then
                printf "  ${CYAN}%2d)${RST}  ${BOLD}%-24s${RST}\n" "$i" "$alias_val"
            else
                printf "  ${CYAN}%2d)${RST}  %-24s\n" "$i" "$alias_val"
            fi
            visible_indices+=("$idx")
            i=$((i+1))
        done

        echo ""
        echo "  ${DIM}Number → add  |  r → remove last  |  R → reset all  |  + key → custom${RST}"
        echo "  ${DIM}B) Back  |  S) Save + build Waybar${RST}"
        echo ""
        ask "[$SLOT]: "
        local input; read -r input

        case "$input" in
            B|b)
                case "$SLOT" in
                    left)   CUR_LEFT=("${editing[@]:-}") ;;
                    center) CUR_CENTER=("${editing[@]:-}") ;;
                    right)  CUR_RIGHT=("${editing[@]:-}") ;;
                esac
                SLOT=""; STATE="slot"; return ;;
            S|s)
                case "$SLOT" in
                    left)   CUR_LEFT=("${editing[@]:-}") ;;
                    center) CUR_CENTER=("${editing[@]:-}") ;;
                    right)  CUR_RIGHT=("${editing[@]:-}") ;;
                esac
                do_build; exit 0 ;;
            r)
                [[ ${#editing[@]} -gt 0 ]] && editing=("${editing[@]:0:$((${#editing[@]}-1))}") ;;
            R)
                editing=() ;;
            +\ *)
                local custom="${input#+ }"
                [[ -n "$custom" ]] && editing+=("$custom") ;;
            ''|*[!0-9]*) ;;
            *)
                local tidx=$((input - 1))
                local vis_count=${#visible_indices[@]}
                if (( tidx >= 0 && tidx < vis_count )); then
                    local real_idx="${visible_indices[$tidx]}"
                    editing+=("${MOD_KEYS[$real_idx]}")
                fi ;;
        esac
    done
}

# ─── Determine required folders from keys ────────────────────────────────────
collect_required_folders() {
    local -a keys=("$@")
    declare -A seen=()

    for key in "${keys[@]}"; do
        local folder="${KEY_TO_FOLDER[$key]:-}"
        if [[ -n "$folder" ]]; then
            if [[ -z "${seen[$folder]:-}" ]]; then
                echo "$folder"
                seen["$folder"]="1"
            fi
            # Container: also collect sub-modules
            local con_dir="$MODULES_DIR/$folder"
            if [[ -f "$con_dir/container.md" ]]; then
                local sub_mods
                sub_mods=$(grep '^modules' "$con_dir/container.md" \
                    | sed 's/modules *= *"\(.*\)"/\1/' | head -1)
                for sub in $sub_mods; do
                    # sub ist Ordnername
                    if [[ -n "${seen[$sub]:-}" ]]; then continue; fi  # skip already-seen
                    if [[ -d "$MODULES_DIR/$sub" ]]; then
                        echo "$sub"
                        seen["$sub"]="1"
                    fi
                done
            fi
        fi
    done
}

# ─── Build groups.json ────────────────────────────────────────────────────────
build_groups_json() {
    local out_dir="$1"
    shift
    local -a left_keys=() center_keys=() right_keys=()

    # Read left / center / right from arguments (separated by "--")
    local section="left"
    for arg in "$@"; do
        case "$arg" in
            "--center") section="center" ;;
            "--right")  section="right"  ;;
            *) case "$section" in
                   left)   left_keys+=("$arg")   ;;
                   center) center_keys+=("$arg") ;;
                   right)  right_keys+=("$arg")  ;;
               esac ;;
        esac
    done

    # Alle Keys zusammen
    local -a all_keys=("${left_keys[@]:-}" "${center_keys[@]:-}" "${right_keys[@]:-}")

    # Include-Liste (nur verwendete Modul-Configs)
    local include_json="[]"
    while IFS= read -r folder; do
        local cfg="$MODULES_DIR/$folder/config.json"
        if [[ -f "$cfg" ]]; then
            include_json=$(echo "$include_json" | jq --arg p "$cfg" '. + [$p]')
        fi
    done < <(collect_required_folders "${all_keys[@]:-}")

    # Gruppen-Arrays als JSON
    local left_json="[]" center_json="[]" right_json="[]"
    for k in "${left_keys[@]:-}";   do left_json=$(echo   "$left_json"   | jq --arg k "$k" '. + [$k]'); done
    for k in "${center_keys[@]:-}"; do center_json=$(echo "$center_json" | jq --arg k "$k" '. + [$k]'); done
    for k in "${right_keys[@]:-}";  do right_json=$(echo  "$right_json"  | jq --arg k "$k" '. + [$k]'); done

    # Basis-Objekt
    local result
    result=$(jq -n \
        --argjson inc  "$include_json" \
        --argjson left "$left_json" \
        --argjson ctr  "$center_json" \
        --argjson rgt  "$right_json" \
        '{
            "include": $inc,
            "group/left":   { "orientation": "horizontal", "modules": $left },
            "group/center": { "orientation": "horizontal", "modules": $ctr  },
            "group/right":  { "orientation": "horizontal", "modules": $rgt  }
        }')

    mkdir -p "$out_dir"
    echo "$result" | jq '.' > "$out_dir/groups.json"
    dbg "groups.json → $out_dir"
}

# ─── config.json bauen ───────────────────────────────────────────────────────
build_config_json() {
    local out_dir="$1" monitor="$2" position="$3" style="$4"
    local base_config="$BASE_DIR/base-${position}/${style}.config.json"
    local groups_file="$out_dir/groups.json"

    [[ -f "$base_config" ]] || { err "Base-Config fehlt: $base_config"; return 1; }
    [[ -f "$groups_file" ]] || { err "groups.json fehlt: $groups_file"; return 1; }

    jq \
        --arg output  "$monitor" \
        --arg id      "${style}-${position}-${monitor}" \
        --arg grp     "$groups_file" \
        '. + {
            "output":         $output,
            "id":             $id,
            "include":        [$grp],
            "modules-left":   ["group/left"],
            "modules-center": ["group/center"],
            "modules-right":  ["group/right"]
        }' "$base_config" | jq '.' > "$out_dir/config.json"

    dbg "config.json → $out_dir"
}

# ─── style.css bauen ─────────────────────────────────────────────────────────
build_style_css() {
    local out_dir="$1" position="$2" style="$3"
    shift 3
    local -a req_folders=("$@")

    local base_css="$BASE_DIR/base-${position}/${style}.css"

    mkdir -p "$out_dir"
    {
        if [[ -f "$base_css" ]]; then
            echo "@import url(\"${base_css}\");"
        fi
        echo ""
        for folder in "${req_folders[@]:-}"; do
            local mod_css="$MODULES_DIR/$folder/style.css"
            if [[ -f "$mod_css" ]]; then
                echo "@import url(\"${mod_css}\");"
            fi
        done
    } > "$out_dir/style.css"

    dbg "style.css → $out_dir"
}

# ─── Eine Bar komplett bauen ──────────────────────────────────────────────────
build_bar() {
    local monitor="$1" position="$2" style="$3"
    shift 3
    # Restliche Args: left_keys... "--center" center_keys... "--right" right_keys...

    local out_dir="$OUTPUT_DIR/$style/$position/$monitor"

    # Build groups.json and config.json
    build_groups_json "$out_dir" "$@"
    build_config_json "$out_dir" "$monitor" "$position" "$style"

    # Required folders for style.css
    local -a all_keys=()
    for arg in "$@"; do
        [[ "$arg" == "--center" || "$arg" == "--right" ]] && continue
        all_keys+=("$arg")
    done

    local -a req_folders=()
    while IFS= read -r f; do req_folders+=("$f"); done \
        < <(collect_required_folders "${all_keys[@]:-}")

    build_style_css "$out_dir" "$position" "$style" "${req_folders[@]:-}"

    ok "Bar: $monitor ($style/$position)"
}

# ─── Interactive main loop ────────────────────────────────────────────────────
main() {
    load_all_modules
    while true; do
        case "$STATE" in
            monitor)  screen_monitor ;;
            position) screen_position ;;
            style)    screen_style ;;
            slot)     screen_slot ;;
            modules)  screen_modules ;;
        esac
    done
}

# ─── Kill + Starten ───────────────────────────────────────────────────────────
kill_and_start() {
    if pgrep -x waybar &>/dev/null; then
        pkill -x waybar || true
        sleep 0.3
    fi

    if [[ -x "$LAUNCH_SCRIPT" ]]; then
        bash "$LAUNCH_SCRIPT"
    else
        err "launch-waybar.sh nicht gefunden: $LAUNCH_SCRIPT"
    fi
}

# ─── Rebuild (without interactive menu) ──────────────────────────────────────
rebuild_all() {
    load_all_modules

    echo "── Waybar Rebuild ──────────────────────────────────"
    echo ""

    local -a out_dirs=()
    while IFS= read -r dir; do out_dirs+=("$dir"); done \
        < <(find "$OUTPUT_DIR" -mindepth 3 -maxdepth 3 -type d 2>/dev/null | sort)

    if [[ ${#out_dirs[@]} -eq 0 ]]; then
        err "No saved configurations in $OUTPUT_DIR"
        echo "  Please run '$0' without --rebuild first."
        exit 1
    fi

    for out_dir in "${out_dirs[@]}"; do
        # Path: output/{style}/{position}/{monitor}
        local rel="${out_dir#$OUTPUT_DIR/}"
        local style position monitor
        style="${rel%%/*}"; rel="${rel#*/}"
        position="${rel%%/*}"; monitor="${rel#*/}"

        dbg "Rebuild: $style/$position/$monitor"

        local groups_file="$out_dir/groups.json"
        [[ -f "$groups_file" ]] || { dbg "No groups.json – skipping $out_dir"; continue; }

        # Read keys from the three main groups
        local -a all_keys=()
        while IFS= read -r k; do
            [[ -n "$k" ]] && all_keys+=("$k")
        done < <(jq -r '
            .["group/left"].modules[]?,
            .["group/center"].modules[]?,
            .["group/right"].modules[]?
        ' "$groups_file" 2>/dev/null || true)

        # Include-Liste neu bauen (Container-Configs jetzt automatisch dabei)
        local new_include="[]"
        local -a req_folders=()
        while IFS= read -r folder; do
            req_folders+=("$folder")
            local cfg="$MODULES_DIR/$folder/config.json"
            if [[ -f "$cfg" ]]; then
                new_include=$(echo "$new_include" | jq --arg p "$cfg" '. + [$p]')
            fi
        done < <(collect_required_folders "${all_keys[@]:-}")

        # groups.json: Include aktualisieren, Inline-Container-Defs entfernen
        jq \
            --argjson inc "$new_include" \
            '{
                "include":      $inc,
                "group/left":   .["group/left"],
                "group/center": .["group/center"],
                "group/right":  .["group/right"]
            }' "$groups_file" | jq '.' > "$groups_file.tmp" \
            && mv "$groups_file.tmp" "$groups_file"

        build_config_json "$out_dir" "$monitor" "$position" "$style"
        build_style_css "$out_dir" "$position" "$style" "${req_folders[@]:-}"

        ok "$monitor ($style/$position)"
    done

    echo ""
    kill_and_start
}

# ─── Entry Point ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--rebuild" ]]; then
    rebuild_all
else
    main "$@"
fi
