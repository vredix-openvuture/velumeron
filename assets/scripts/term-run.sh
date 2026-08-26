#!/usr/bin/env bash
# term-run.sh <app-id> <title> <command…>
#
# Open a terminal window running <command>, in WHATEVER emulator this user actually has. All of the
# "which emulator, and how does it spell --class" knowledge lives in lib/term.sh, shared with
# btop-drop.sh and the launcher's Terminal=true entries.
#
# Nothing here themes the terminal any more: the emulator reads its OWN config, which velumeron
# only touches if you switched that terminal on in Settings → Integrations → Terminal.
_dir="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$_dir/lib/env.sh"
source "$_dir/lib/term.sh"

APPID="${1:-velumeron-term}"; shift || true
TITLE="${1:-Velumeron}";      shift || true
CMD="$*"
[[ -z "$CMD" ]] && { echo "usage: term-run.sh <app-id> <title> <command…>" >&2; exit 1; }

TERM_BIN="$(vtl_term_bin)"
if [[ -z "$TERM_BIN" ]]; then
    notify-send "Velumeron" "No terminal emulator found — set \$TERMINAL or install one." 2>/dev/null
    exit 1
fi

vtl_term_argv "$TERM_BIN" "$APPID" "$TITLE" "$CMD"
exec "${VTL_TERM_ARGV[@]}"
