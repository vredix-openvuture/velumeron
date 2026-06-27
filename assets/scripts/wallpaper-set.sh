#!/usr/bin/env bash
# wallpaper-set.sh [--no-showcase] [--no-waybar] (--set SET_ID | [--hor FILE] [--ver FILE])
#   --no-waybar : don't kill/launch/signal waybar (use when quickshell is the active bar)
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

showcase=true
no_waybar=false
set_id=""
hor_file=""
ver_file=""
WP_H="$WALLPAPER_DIR_H"
WP_V="$WALLPAPER_DIR_V"
SETS_JSON="$VUTURELAND_USER_DIR/assets/sets.json"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-showcase) showcase=false; shift ;;
        --no-waybar)   no_waybar=true; shift ;;
        --set)         set_id="$2"; shift 2 ;;
        --hor)         hor_file="$2"; shift 2 ;;
        --ver)         ver_file="$2"; shift 2 ;;
        *)
            file="$1"; shift
            stem=$(basename "${file%.*}")
            if [[ "$stem" == *"_ver"* ]]; then ver_file="$file"
            else hor_file="$file"; fi
            ;;
    esac
done

if [[ -z "$set_id" && -z "$hor_file" && -z "$ver_file" ]]; then
    echo "Usage: wallpaper-set.sh [--no-showcase] (--set SET_ID | [--hor FILE] [--ver FILE])"
    exit 1
fi

# ── Wallust source — derive the colour theme from the MAIN (focused) monitor's
# wallpaper, so the theme only changes when the main monitor's wallpaper is
# swapped (changing a secondary monitor leaves the theme untouched). ──────────
_main_mon=$(hyprctl monitors -j 2>/dev/null | jq -r '[.[] | select(.focused)][0].name' 2>/dev/null)
[[ -z "$_main_mon" || "$_main_mon" == "null" ]] && \
    _main_mon=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name' 2>/dev/null)
_main_vertical=$(hyprctl monitors -j 2>/dev/null | jq -r \
    --arg m "$_main_mon" '[.[] | select(.name==$m)][0] | ((.transform%2)==1) or (.height > .width)' 2>/dev/null)

if [[ -n "$set_id" && -f "$SETS_JSON" ]]; then
    # the file the set assigns to the main monitor (explicit, else by orientation)
    wf=$(jq -r --arg sid "$set_id" --arg m "$_main_mon" \
        '.[$sid].images[] | select(.monitor==$m) | .file' "$SETS_JSON" 2>/dev/null | head -1)
    if [[ -z "$wf" ]]; then
        if [[ "$_main_vertical" == "true" ]]; then _o="_ver"; else _o="_hor"; fi
        wf=$(jq -r --arg sid "$set_id" --arg o "$_o" \
            '.[$sid].images[] | select(.file | contains($o)) | .file' "$SETS_JSON" 2>/dev/null | head -1)
    fi
    [[ -n "$wf" ]] && wallust_src=$(find "$WP_H" "$WP_V" -maxdepth 1 -name "$wf" 2>/dev/null | head -1)
elif [[ "$_main_vertical" == "true" ]]; then
    wallust_src="$ver_file"   # main is vertical → theme from the vertical wallpaper
else
    wallust_src="$hor_file"   # main is horizontal → theme from the horizontal one
fi

# ── Showcase: save workspaces ─────────────────────────────────────────────
if [[ "$showcase" == "true" ]]; then
    focused_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name')
    mapfile -t monitors < <(hyprctl monitors -j | jq -r '.[].name')
    original_workspaces=()
    for mon in "${monitors[@]}"; do
        ws=$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | .activeWorkspace.id')
        original_workspaces+=("$ws")
    done
    i=0
    for mon in "${monitors[@]}"; do
        hyprctl dispatch "hl.dsp.focus({monitor=\"${mon}\"})"
        hyprctl dispatch "hl.dsp.focus({workspace=$((111 + i))})"
        i=$((i + 1))
    done
fi

[[ "$no_waybar" == true ]] || killall waybar 2>/dev/null || true
pkill -f mpvpaper 2>/dev/null || true

# ── Apply wallpaper per monitor ───────────────────────────────────────────
while IFS=';' read -r mon_name transform width height; do
    is_vertical=false
    if [[ "$transform" == "1" || "$transform" == "3" ]] || (( height > width )); then
        is_vertical=true
    fi

    if [[ -n "$set_id" && -f "$SETS_JSON" ]]; then
        # 1. Explicit monitor assignment in set
        file=$(jq -r --arg sid "$set_id" --arg mon "$mon_name" \
            '.[$sid].images[] | select(.monitor == $mon) | .file' \
            "$SETS_JSON" 2>/dev/null | head -1)
        # 2. Orientation fallback
        if [[ -z "$file" ]]; then
            if "$is_vertical"; then orient="_ver"; else orient="_hor"; fi
            file=$(jq -r --arg sid "$set_id" --arg o "$orient" \
                '.[$sid].images[] | select(.monitor == null and (.file | contains($o))) | .file' \
                "$SETS_JSON" 2>/dev/null | head -1)
        fi
        [[ -n "$file" ]] \
            && filepath=$(find "$WP_H" "$WP_V" -maxdepth 1 -name "$file" 2>/dev/null | head -1) \
            || filepath=""
    else
        # Legacy --hor / --ver mode
        if "$is_vertical"; then filepath="$ver_file"; else filepath="$hor_file"; fi
    fi

    [[ -z "$filepath" || ! -f "$filepath" ]] && continue

    ext="${filepath##*.}"
    case "${ext,,}" in
        mp4|webm|mkv|avi|mov)
            mpvpaper -o "no-audio loop" "$mon_name" "$filepath" & disown ;;
        *)
            awww img -o "$mon_name" \
                --transition-type wipe --transition-angle 120 \
                --transition-step 200 --transition-fps 200 --transition-duration 2 \
                "$filepath" ;;
    esac
done < <(hyprctl monitors -j | jq -r '.[] | "\(.name);\(.transform);\(.width);\(.height)"')

# ── Wallust ───────────────────────────────────────────────────────────────
_run_wallust_hooks() {
    "$VUTURELAND_DIR/assets/scripts/wallust/hyprland_lua-colors.sh" && hyprctl reload
    pywalfox update &>/dev/null &
    [[ "$no_waybar" == true ]] || { sleep 0.8 && pkill -SIGUSR2 waybar; } &
}

_color_mode=$(cat "$VUTURELAND_USER_DIR/wallust/color-mode" 2>/dev/null || echo "auto")

if [[ -n "$wallust_src" && "$_color_mode" == "auto" ]]; then
    ext="${wallust_src##*.}"
    case "${ext,,}" in
        mp4|webm|mkv|avi|mov)
            tmp=$(mktemp /tmp/wp-frame-XXXXXX.jpg)
            ffmpeg -y -i "$wallust_src" -vframes 1 -q:v 2 "$tmp" &>/dev/null
            wallust --config-dir "$VUTURELAND_DIR/wallust" run "$tmp"
            rm -f "$tmp" ;;
        *)
            wallust --config-dir "$VUTURELAND_DIR/wallust" run "$wallust_src" ;;
    esac
elif [[ "$_color_mode" == fixed:* ]]; then
    _scheme_file="$VUTURELAND_DIR/wallust/fixed_colors/${_color_mode#fixed:}"
    if [[ -f "$_scheme_file" ]]; then
        wallust --config-dir "$VUTURELAND_DIR/wallust" cs "$_scheme_file"
        _run_wallust_hooks
    fi
fi

# ── Restore workspaces ────────────────────────────────────────────────────
if [[ "$showcase" != "true" && "$no_waybar" != "true" ]]; then
    "$VUTURELAND_DIR/assets/scripts/launch-waybar.sh" &
fi

if [[ "$showcase" == "true" ]]; then
    sleep 2
    [[ "$no_waybar" == "true" ]] || "$VUTURELAND_DIR/assets/scripts/launch-waybar.sh"
    i=0
    for mon in "${monitors[@]}"; do
        hyprctl dispatch "hl.dsp.focus({monitor=\"${mon}\"})"
        hyprctl dispatch "hl.dsp.focus({workspace=${original_workspaces[$i]}})"
        i=$((i + 1))
    done
    i=$(( ${#monitors[@]} - 1 ))
    while (( i >= 0 )); do
        hyprctl dispatch "hl.dsp.focus({monitor=\"${monitors[$i]}\"})"
        hyprctl dispatch "hl.dsp.focus({workspace=${original_workspaces[$i]}})"
        i=$((i - 1))
    done
    hyprctl dispatch "hl.dsp.focus({monitor=\"${focused_monitor}\"})"
fi
