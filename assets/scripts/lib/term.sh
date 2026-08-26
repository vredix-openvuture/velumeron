#!/usr/bin/env bash
# Terminal emulator library — WHICH emulator, and how to ask it for a window.
#
# The shell used to spawn `kitty` by name in three places (term-run.sh, btop-drop.sh, the
# launcher's Terminal=true entries) and pass it a velumeron kitty.conf from the user dir. That made
# one emulator a hard dependency of the desktop. It is now a role app like the browser or the file
# manager: whatever you actually have gets used, and THEMING it is a separate opt-in
# (Settings → Integrations → Terminal, which writes that emulator's own config).
#
# Source it, then:
#     vtl_term_bin                                  → the emulator to use, or "" if none
#     vtl_term_argv <bin> <app-id> <title> <cmd…>   → fills VTL_TERM_ARGV with the full argv
#     vtl_term_string <bin> <app-id> <title> <cmd…> → the same, shell-quoted as ONE string
#
# The app-id matters because window rules key off it (a floating, blurred update window, the btop
# dropdown); every emulator spells that flag differently, which is what this file exists for.

# Candidate order: the emulators velumeron can theme first (Settings → Integrations → Terminal),
# then the rest of the common field, so a machine with none of ours still gets a window.
VTL_TERM_CANDIDATES=(kitty foot alacritty wezterm ghostty rio konsole gnome-terminal xfce4-terminal xterm)

# Which terminal?
#   1. $VELUMERON_TERMINAL   — explicit override
#   2. $TERMINAL             — the usual convention, honoured by many tools
#   3. `terminal = …` from user_settings.lua (the role app the keybinds use)
#   4. the first installed candidate
vtl_term_bin() {
    local t
    for t in "${VELUMERON_TERMINAL:-}" "${TERMINAL:-}"; do
        [[ -n "$t" ]] && command -v "${t%% *}" >/dev/null 2>&1 && { echo "${t%% *}"; return; }
    done
    local us="${VELUMERON_USER_DIR:-$HOME/.config/velumeron}/hypr.lua/user_settings.lua"
    if [[ -f "$us" ]]; then
        t=$(sed -n 's/^[[:space:]]*terminal[[:space:]]*=[[:space:]]*["'\'']\([^"'\'']*\).*/\1/p' "$us" | head -1)
        t="${t%% *}"
        [[ -n "$t" ]] && command -v "$t" >/dev/null 2>&1 && { echo "$t"; return; }
    fi
    for t in "${VTL_TERM_CANDIDATES[@]}"; do
        command -v "$t" >/dev/null 2>&1 && { echo "$t"; return; }
    done
    echo ""
}

# Build the argv for "<bin>, in a window called <app-id>/<title>, running <cmd>".
# `bash -lc` throughout: the callers pass a command LINE (with pipes and env prefixes), not an argv.
#
# VTL_TERM_OPTS — one-shot `-o key=value` overrides, for the callers that need a window to behave
# differently just this once (the btop dropdown: no remembered size, wider padding). Only kitty
# takes them; everywhere else they are silently dropped, which is the right outcome — the window
# still opens, it just keeps that emulator's own padding.
VTL_TERM_ARGV=()
VTL_TERM_OPTS=()
vtl_term_argv() {
    local bin="$1" appid="$2" title="$3"; shift 3
    local cmd="$*"
    case "$(basename "$bin")" in
        kitty)          VTL_TERM_ARGV=("$bin" --class "$appid" --title "$title"
                                       ${VTL_TERM_OPTS[@]+"${VTL_TERM_OPTS[@]}"} bash -lc "$cmd") ;;
        foot)           VTL_TERM_ARGV=("$bin" --app-id "$appid" --title "$title" bash -lc "$cmd") ;;
        alacritty)      VTL_TERM_ARGV=("$bin" --class "$appid" --title "$title" -e bash -lc "$cmd") ;;
        wezterm)        VTL_TERM_ARGV=("$bin" start --class "$appid" -- bash -lc "$cmd") ;;
        ghostty)        VTL_TERM_ARGV=("$bin" "--class=$appid" "--title=$title" -e bash -lc "$cmd") ;;
        rio)            VTL_TERM_ARGV=("$bin" --title-placeholder "$title" -e bash -lc "$cmd") ;;
        konsole)        VTL_TERM_ARGV=("$bin" -p "tabtitle=$title" -e bash -lc "$cmd") ;;
        gnome-terminal) VTL_TERM_ARGV=("$bin" --title "$title" -- bash -lc "$cmd") ;;
        xfce4-terminal) VTL_TERM_ARGV=("$bin" --title "$title" -e "bash -lc $(printf '%q' "$cmd")") ;;
        xterm)          VTL_TERM_ARGV=("$bin" -class "$appid" -T "$title" -e bash -lc "$cmd") ;;
        *)              VTL_TERM_ARGV=("$bin" -e bash -lc "$cmd") ;;   # -e is the closest thing to a convention
    esac
}

# The same argv, quoted into one string — for the callers that hand a COMMAND LINE to something
# else (hyprctl's exec_cmd, a .desktop Exec=).
vtl_term_string() {
    vtl_term_argv "$@"
    local out="" a
    for a in "${VTL_TERM_ARGV[@]}"; do out+="${out:+ }$(printf '%q' "$a")"; done
    printf '%s' "$out"
}
