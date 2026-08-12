#!/usr/bin/env bash
# screenshot.sh MODE [--geom "X,Y WxH"] [--output NAME] [--no-copy] [--no-save]
#                    [--delay N] [--open]
#
# NO CURSOR OPTION, deliberately — see the amdgpu note below. Do not add one back.
#
#   MODE   region | window | output | all
#
# Replaces the bare `hyprshot -z --mode region` the SUPER+SHIFT+S bind used to run. hyprshot is a
# fine wrapper, but it decides the mode at bind time — the whole point of the picker overlay is that
# the mode is a decision you make when you press the key, not one baked into a config file a month
# ago. This talks to grim/slurp directly so every mode and the delay come from one
# place, and so the notification can carry an action.
#
# Always exits promptly: the notification (which WAITS for a click, that is what -A does) is handed
# to a detached child, so the shell that fired this is not left holding it open.
set -uo pipefail
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh" 2>/dev/null || true

mode="${1:-region}"; shift || true
copy=true; save=true; delay=0; open_after=false
# The picker hands these in from the moment the key was pressed. Asking the compositor AFTER the
# overlay has come and gone means asking about a focus state the overlay itself disturbed — the
# window you wanted may not be the active one any more.
geom=""; out_name=""

while (($#)); do
    case "$1" in
        --no-copy) copy=false;   shift ;;
        --no-save) save=false;   shift ;;
        --open)    open_after=true; shift ;;
        --delay)   delay="${2:-0}"; shift 2 ;;
        --geom)    geom="${2:-}";   shift 2 ;;
        --output)  out_name="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done

dir="${SCREENSHOT_DIR:-$HOME/Bilder/Screenshots}"
mkdir -p "$dir"
file="$dir/$(date +%Y-%m-%d-%H%M%S)_velumeron.png"

(( delay > 0 )) && sleep "$delay"

# `grim -c` IS NOT COMING BACK. It froze the machine hard enough to need the power button — the
# kernel log says `amdgpu [drm] *ERROR* [CRTC:369:crtc-0] flip_done timed out`, which is the display
# pipeline wedging at DRM level, which is why not even a VT switch worked.
#
# It is the one thing this script did that hyprshot never did. hyprshot has no cursor option at all
# and ran here for months; it even passes the same full-size PNG as the notification icon, so that
# was never the difference. Compositing the cursor plane into a screencopy is, and on this amdgpu it
# takes the CRTC with it.
grim_args=()

case "$mode" in
    region)
        # `</dev/null` IS THE WHOLE FIX, and it took far too long to find. slurp reads a list of
        # predefined regions from stdin when stdin is not a terminal. Run from a shell, stdin is a
        # TTY and slurp draws. Run from quickshell, stdin is a PIPE — so slurp blocked on
        # anon_pipe_read forever: alive, silent, no Wayland surface, no error, nothing on screen.
        # Which is exactly "I click Selection and nothing happens".
        #
        # grim was never affected, which is why every other mode worked and made this look like a
        # QML problem. It was never a QML problem.
        #
        # slurp writes nothing and exits non-zero when you press Escape — that is a cancel, not a
        # failure, and it must not leave a notification behind.
        geo=$(slurp -d </dev/null 2>/dev/null) || exit 0
        [[ -z "$geo" ]] && exit 0
        grim_args+=(-g "$geo")
        ;;
    window)
        geo="$geom"
        [[ -z "$geo" ]] && geo=$(hyprctl activewindow -j 2>/dev/null \
              | jq -r 'select(.at != null) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' 2>/dev/null)
        [[ -z "$geo" || "$geo" == "null" ]] && { notify-send -a Velumeron -u low \
            "No window" "Nothing focused to capture." >/dev/null 2>&1 & exit 0; }
        grim_args+=(-g "$geo")
        ;;
    output)
        mon="$out_name"
        [[ -z "$mon" ]] && mon=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor // empty' 2>/dev/null)
        [[ -n "$mon" ]] && grim_args+=(-o "$mon")
        ;;
    all) ;;                                   # every output, grim's default
    *)   echo "screenshot: unknown mode: $mode" >&2; exit 2 ;;
esac

if ! grim "${grim_args[@]}" "$file" 2>/dev/null; then
    notify-send -a Velumeron -u critical "Screenshot failed" "grim could not capture $mode." >/dev/null 2>&1 &
    exit 1
fi

$copy && wl-copy --type image/png < "$file" 2>/dev/null

# --open was asked for explicitly: no need to make you click a notification you already decided on.
if $open_after; then
    setsid -f xdg-open "$file" >/dev/null 2>&1
fi

# The notification IS the receipt, and clicking it opens the shot. -A implies --wait, so this blocks
# until you click or it expires — hence the detached subshell. `default` is the action id velumeron's
# own notification service invokes on a plain click (NotifService.defaultActionOf).
(
    # -t alongside -A: `-A` implies --wait, and with no timeout this process sits forever holding a
    # notification open. hyprshot passes a timeout for the same reason.
    # x-velumeron-silent: the shutter has already sounded (ShotRunner plays it the moment grim
    # exits 0). Without this the "saved" toast fires the notification sound straight after it, so
    # one screenshot made two different noises.
    act=$(notify-send -a Velumeron -t 8000 -A default=Open -i "$file" \
                      -h string:x-velumeron-silent:1 \
                      "Screenshot saved" "$(basename "$file")$($copy && echo ' · copied')" 2>/dev/null)
    [[ "$act" == "default" ]] && ! $open_after && setsid -f xdg-open "$file" >/dev/null 2>&1
) >/dev/null 2>&1 &

if ! $save; then
    # Clipboard-only: wl-copy has read the file already, and the notification holds no reference
    # worth keeping beyond its icon. Give both a beat, then take the file back.
    ( sleep 8; rm -f "$file" ) >/dev/null 2>&1 &
fi

exit 0
