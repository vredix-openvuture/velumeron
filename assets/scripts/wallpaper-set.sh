#!/usr/bin/env bash
# wallpaper-set.sh [--no-showcase] [--no-waybar] (--set SET_ID | [--hor FILE] [--ver FILE])
#   --no-waybar : don't kill/launch/signal waybar (use when quickshell is the active bar)
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

showcase=true
no_waybar=false
set_id=""
hor_file=""
ver_file=""
mon_arg=""        # per-monitor single apply (new model): set just this monitor …
file_arg=""       # … to this file. Independent of --hor/--ver/--set.
WP_H="$WALLPAPER_DIR_H"
WP_V="$WALLPAPER_DIR_V"
SETS_JSON="$VELUMERON_USER_DIR/assets/sets.json"

# Serialize wallust across concurrent wallpaper applies. `wallust run` renders colors.lua AND runs
# its [hooks] (hex→rgb + hyprctl reload) every time; two overlapping runs race on that file and
# corrupt it with NUL bytes → broken Hyprland config (emergency error). The new per-monitor menus
# make rapid swaps easy, so guard every wallust invocation with a file lock.
WALLUST_LOCK="${XDG_RUNTIME_DIR:-/tmp}/vtl-wallust.lock"
# -n (non-blocking): if another wallust is already running, SKIP this theme update instead of
# queuing. Prevents the colors.lua race (only one wallust writes at a time) without ever piling up a
# queue of stuck applies — the wallpaper itself was already applied above; only the recolour is
# skipped for a rapid second click.
#
# Split run: wallust broadcasts colour sequences to EVERY /dev/pts/* before templating, and a
# pty that is never read (gvfsd-sftp's ssh ptys, dead terminals) blocks that write forever —
# which froze the whole colour pipeline while holding the lock. So the main run skips
# sequences (-s: templates + hooks always land), and a follow-up sequences-only pass (-T)
# recolours live terminals best-effort, hard-reaped if it hits a blocked pty. The timeout on
# the main run is belt-and-braces against any other way wallust finds to never exit.
_wallust() {
    local sub="$1"; shift
    timeout -k 5 30 flock -n "$WALLUST_LOCK" \
        wallust --config-dir "$VELUMERON_DIR/wallust" "$sub" -s "$@" || return
    ( timeout -k 2 5 wallust --config-dir "$VELUMERON_DIR/wallust" "$sub" -T -q "$@" >/dev/null 2>&1 & )
}

# Native wallpaper engine: upsert this monitor's entry in wallpapers.json. Quickshell watches the file
# and crossfades in place (static image or live video by extension) — no awww/mpvpaper, no spawn. The
# write is atomic (temp + rename) so the watching FileView never sees a half-written file.
_engine_set() {
    local mon="$1" file="$2" type="image" ext="${2##*.}"
    case "${ext,,}" in mp4|webm|mkv|avi|mov) type="video";; esac
    python3 - "$mon" "$file" "$type" <<'PY'
import json, os, sys
mon, file, typ = sys.argv[1], sys.argv[2], sys.argv[3]
pu = os.environ.get('VELUMERON_USER_DIR') or os.path.expanduser('~/.config/velumeron')
p  = os.path.join(pu, 'quickshell', 'wallpapers.json')
os.makedirs(os.path.dirname(p), exist_ok=True)
try:    d = json.load(open(p))
except Exception: d = {}
d[mon] = {'path': file, 'type': typ}
tmp = p + '.tmp'; open(tmp, 'w').write(json.dumps(d, indent=2)); os.replace(tmp, p)
PY
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-showcase) showcase=false; shift ;;
        --no-waybar)   no_waybar=true; shift ;;
        --set)         set_id="$2"; shift 2 ;;
        --hor)         hor_file="$2"; shift 2 ;;
        --ver)         ver_file="$2"; shift 2 ;;
        --mon)         mon_arg="$2"; shift 2 ;;
        --file)        file_arg="$2"; shift 2 ;;
        *)
            file="$1"; shift
            stem=$(basename "${file%.*}")
            if [[ "$stem" == *"_ver"* ]]; then ver_file="$file"
            else hor_file="$file"; fi
            ;;
    esac
done

if [[ -z "$set_id" && -z "$hor_file" && -z "$ver_file" && ( -z "$mon_arg" || -z "$file_arg" ) ]]; then
    echo "Usage: wallpaper-set.sh [--no-showcase] (--set SET_ID | --mon NAME --file FILE | [--hor FILE] [--ver FILE])"
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

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# DISPLAY BACKEND: native Velumeron engine. This script no longer paints wallpapers itself — it writes
# each monitor's choice into wallpapers.json (via _engine_set) and the quickshell WallpaperWindow draws
# it (static image or live video) with a GPU crossfade. wallust still derives the colour theme. Both the
# per-monitor (--mon/--file) and the legacy (--hor/--ver/--set) paths funnel through _engine_set; the
# old awww/mpvpaper + workspace-"showcase" machinery is gone (the crossfade is clean over windows).
# ═══════════════════════════════════════════════════════════════════════════════════════════════

# ── Per-monitor single apply (per-monitor picker / quick-menu) ──────────────────────────────────
# Set exactly ONE monitor and leave the others untouched; derive the colour theme only when the
# main (focused) monitor's wallpaper changed. Fully separate from the legacy --hor/--ver/--set path.
if [[ -n "$mon_arg" && -n "$file_arg" ]]; then
    [[ -f "$file_arg" ]] || { echo "wallpaper-set: file not found: $file_arg" >&2; exit 1; }
    _ext="${file_arg##*.}"

    # Native engine: hand this monitor's wallpaper to quickshell, which crossfades it in place (static
    # image or live video). No awww/mpvpaper, and no workspace "showcase" — the GPU crossfade is clean.
    _engine_set "$mon_arg" "$file_arg"

    # Derive the colour theme only when the MAIN (focused) monitor's wallpaper changed (image, or a
    # video's first frame). wallust's own [hooks] update colors.json — quickshell recolours live.
    _cmode=$(cat "$VELUMERON_USER_DIR/wallust/color-mode" 2>/dev/null || echo "auto")
    if [[ "$mon_arg" == "$_main_mon" && "$_cmode" == "auto" ]]; then
        case "${_ext,,}" in
            mp4|webm|mkv|avi|mov)
                _tmp=$(mktemp /tmp/wp-frame-XXXXXX.jpg)
                ffmpeg -y -i "$file_arg" -vframes 1 -q:v 2 "$_tmp" &>/dev/null
                _wallust run "$_tmp"; rm -f "$_tmp" ;;
            *)  _wallust run "$file_arg" ;;
        esac
    fi
    exit 0
fi

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

# ── Apply wallpaper per monitor (hand each to the native engine) ──────────
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

    _engine_set "$mon_name" "$filepath"
done < <(hyprctl monitors -j | jq -r '.[] | "\(.name);\(.transform);\(.width);\(.height)"')

# ── Wallust ───────────────────────────────────────────────────────────────
_run_wallust_hooks() {
    "$VELUMERON_DIR/assets/scripts/wallust/hyprland_lua-colors.sh" && hyprctl reload
    pywalfox update &>/dev/null &
}

_color_mode=$(cat "$VELUMERON_USER_DIR/wallust/color-mode" 2>/dev/null || echo "auto")

if [[ -n "$wallust_src" && "$_color_mode" == "auto" ]]; then
    ext="${wallust_src##*.}"
    case "${ext,,}" in
        mp4|webm|mkv|avi|mov)
            tmp=$(mktemp /tmp/wp-frame-XXXXXX.jpg)
            ffmpeg -y -i "$wallust_src" -vframes 1 -q:v 2 "$tmp" &>/dev/null
            _wallust run "$tmp"
            rm -f "$tmp" ;;
        *)
            _wallust run "$wallust_src" ;;
    esac
elif [[ "$_color_mode" == fixed:* ]]; then
    _scheme_file="$VELUMERON_DIR/wallust/fixed_colors/${_color_mode#fixed:}"
    if [[ -f "$_scheme_file" ]]; then
        _wallust cs "$_scheme_file"
        _run_wallust_hooks
    fi
fi
