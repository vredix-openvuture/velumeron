#!/usr/bin/env bash
# term-run.sh <app-id> <title> <command…>
#
# Open a terminal window running <command>, in WHATEVER emulator this user actually has. The shell
# used to spawn `kitty` by name, which is fine here and wrong everywhere else — the terminal is a
# role app (hypr.lua's `terminal`), not a fixed dependency.
#
# Resolution order:
#   1. $VELUMERON_TERMINAL   — explicit override
#   2. $TERMINAL             — the usual convention, honoured by many tools
#   3. `terminal = …` from user_settings.lua (the role app the keybinds use)
#   4. the first installed of a candidate list
#
# The app-id matters because window rules key off it (a floating, blurred update window); every
# emulator spells that flag differently, which is the other half of what this script exists for.
# Only kitty gets the velumeron kitty.conf — for the others the user's own config stays untouched.
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

APPID="${1:-velumeron-term}"; shift || true
TITLE="${1:-Velumeron}";      shift || true
CMD="$*"
[[ -z "$CMD" ]] && { echo "usage: term-run.sh <app-id> <title> <command…>" >&2; exit 1; }

# ── Which terminal? ──────────────────────────────────────────────────────────────────────────────
pick() {
    local t
    for t in "${VELUMERON_TERMINAL:-}" "${TERMINAL:-}"; do
        [[ -n "$t" ]] && command -v "${t%% *}" >/dev/null 2>&1 && { echo "${t%% *}"; return; }
    done
    # The role app from user_settings.lua: `terminal = "kitty …"` / `terminal = 'foot'`
    local us="$VELUMERON_USER_DIR/hypr.lua/user_settings.lua"
    if [[ -f "$us" ]]; then
        t=$(sed -n 's/^[[:space:]]*terminal[[:space:]]*=[[:space:]]*["'\'']\([^"'\'']*\).*/\1/p' "$us" | head -1)
        t="${t%% *}"
        [[ -n "$t" ]] && command -v "$t" >/dev/null 2>&1 && { echo "$t"; return; }
    fi
    for t in kitty foot alacritty wezterm ghostty konsole gnome-terminal xfce4-terminal xterm; do
        command -v "$t" >/dev/null 2>&1 && { echo "$t"; return; }
    done
    echo ""
}
TERM_BIN="$(pick)"
if [[ -z "$TERM_BIN" ]]; then
    notify-send "Velumeron" "No terminal emulator found — set \$TERMINAL or install one." 2>/dev/null
    exit 1
fi

# ── Spawn, with each emulator's own spelling of app-id / title / command ─────────────────────────
KCONF="$VELUMERON_USER_DIR/kitty/kitty.conf"
case "$(basename "$TERM_BIN")" in
    kitty)
        args=(--class "$APPID" --title "$TITLE")
        [[ -f "$KCONF" ]] && args+=(-c "$KCONF")      # wallust colours, only for our own terminal
        exec "$TERM_BIN" "${args[@]}" bash -lc "$CMD" ;;
    foot)
        exec "$TERM_BIN" --app-id "$APPID" --title "$TITLE" bash -lc "$CMD" ;;
    alacritty)
        exec "$TERM_BIN" --class "$APPID" --title "$TITLE" -e bash -lc "$CMD" ;;
    wezterm)
        exec "$TERM_BIN" start --class "$APPID" -- bash -lc "$CMD" ;;
    ghostty)
        exec "$TERM_BIN" --class="$APPID" --title="$TITLE" -e bash -lc "$CMD" ;;
    konsole)
        exec "$TERM_BIN" -p tabtitle="$TITLE" -e bash -lc "$CMD" ;;
    gnome-terminal)
        exec "$TERM_BIN" --title "$TITLE" -- bash -lc "$CMD" ;;
    xfce4-terminal)
        exec "$TERM_BIN" --title "$TITLE" -e "bash -lc $(printf '%q' "$CMD")" ;;
    xterm)
        exec "$TERM_BIN" -class "$APPID" -T "$TITLE" -e bash -lc "$CMD" ;;
    *)
        # Unknown emulator: -e is the closest thing to a convention.
        exec "$TERM_BIN" -e bash -lc "$CMD" ;;
esac
