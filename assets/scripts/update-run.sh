#!/usr/bin/env bash
# update-run.sh "<update command>" [--no-aur] [--no-flatpak]
#
# The terminal session behind the bar's Updates module. Clicking that module used to drop you into
# a bare `yay -Syu`, which opens with a naked sudo prompt and no idea what it is about to do. This
# wraps the very same command in something that reads like part of the shell:
#
#   • the Velumeron banner at the top, by the best means the terminal offers (see banner())
#   • what is pending, in the CURRENT wallust palette — repo / AUR / flatpak, old → new per package
#   • a framed, coloured sudo prompt (SUDO_PROMPT) instead of "[sudo] password for vredix:"
#   • how long it took, and a keypress to close
#
# NOTHING here assumes a particular terminal: colours are plain 24-bit ANSI, the banner degrades
# from kitty's graphics protocol → coloured block art → a framed wordmark, and the caller
# (term-run.sh) picks whatever emulator the user actually runs.
#
# The update command itself is untouched — whatever is configured in the module runs verbatim, so
# this only changes what you SEE around it.
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

CMD="${1:-yay -Syu}"
shift || true
CHECK_FLAGS=("$@")

# ── Palette → 24-bit ANSI (falls back to sane defaults when the file isn't there yet) ────────────
eval "$(python3 - "$VELUMERON_USER_DIR/quickshell/colors.json" <<'PY'
import json, sys

def esc(hex_, bold=False):
    h = (hex_ or "").lstrip("#")
    if len(h) != 6:
        return ""
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return "\\033[%s38;2;%d;%d;%dm" % ("1;" if bold else "", r, g, b)

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        c = json.load(f)
except Exception:
    c = {}

# The SAME role mapping the shell itself uses (Colors.qml): fgBright=color15, fgPrimary=color7,
# fgMuted=color8, accent=color3. A wallust palette has no reliable "green", so success is spelled
# with the bright foreground and emphasis with the accent — never with a hard-coded hue.
bright = esc(c.get("color15") or c.get("foreground"), True) or "\\033[1m"
fg     = esc(c.get("color7")  or c.get("foreground"))       or "\\033[0m"
muted  = esc(c.get("color8"))                               or "\\033[2m"
acc    = esc(c.get("color3"), True)                         or "\\033[1;36m"
print("ACC=$'%s'"   % acc)
print("FG=$'%s'"    % fg)
print("DIM=$'%s'"   % muted)
print("OK=$'%s'"    % bright)
PY
)"
RST=$'\033[0m'
COLS=$(tput cols 2>/dev/null || echo 80)
# Repeat a (possibly multi-byte) character n times. NOT `tr ' ' '─'`: tr maps BYTES, and ─ is three
# of them, so that turns a rule into mojibake.
rep()  { local n=$1 c=$2 s='' i; for ((i = 0; i < n; i++)); do s+="$c"; done; printf '%s' "$s"; }
rule() { printf '  %s%s%s\n' "$DIM" "$(rep $((COLS - 4)) '─')" "$RST"; }

# ── Banner ───────────────────────────────────────────────────────────────────────────────────────
# Three tiers, best first, each a strict fallback of the one before — so this looks intentional in
# kitty, still shows the mark in foot/alacritty/wezterm with chafa around, and never breaks in a
# plain xterm.
BANNER="$VELUMERON_DIR/assets/icons/velumeron_banner-white.png"
banner_text() {
    local word='V E L U M E R O N'
    local w=$(( COLS > 46 ? 42 : COLS - 6 ))
    local pad=$(( (w - ${#word}) / 2 ))
    printf '\n  %s╭%s╮%s\n' "$DIM" "$(rep "$w" '─')" "$RST"
    printf '  %s│%s%s%s%s%s%s│%s\n' "$DIM" "$RST" "$(rep "$pad" ' ')" \
           "$ACC$word$RST" "$(rep $(( w - ${#word} - pad )) ' ')" "$DIM" "$DIM" "$RST"
    printf '  %s╰%s╯%s\n\n' "$DIM" "$(rep "$w" '─')" "$RST"
}
banner() {
    [[ -f "$BANNER" ]] || { banner_text; return; }
    # 1) kitty: the real image, inline via the graphics protocol.
    if [[ -n "${KITTY_WINDOW_ID:-}" || "${TERM:-}" == xterm-kitty* ]] && command -v kitten >/dev/null 2>&1; then
        local rows=8
        if kitten icat --align center --place "${COLS}x${rows}@0x1" "$BANNER" 2>/dev/null; then
            tput cup $((rows + 2)) 0 2>/dev/null || printf '\n'
            return
        fi
    fi
    # 2) any terminal, if chafa is around: the image as 24-bit block art. (img2txt is deliberately
    # NOT used as a further fallback — its 8-colour output looks worse than the clean text box.)
    if command -v chafa >/dev/null 2>&1; then
        printf '\n'
        chafa --size "$((COLS - 4))x9" --align center "$BANNER" 2>/dev/null && { printf '\n'; return; }
    fi
    # 3) plain text, always works.
    banner_text
}
clear
banner

# ── What is pending ──────────────────────────────────────────────────────────────────────────────
printf '  %sSYSTEM UPDATE%s\n' "$ACC" "$RST"
rule
# The JSON travels as an ARGUMENT, not through a pipe: `python3 - <<'PY'` already claims stdin for
# the program itself, so a pipe into it would be swallowed (and every run would read "0 updates").
PENDING="$("$VELUMERON_DIR/assets/scripts/update-check.sh" "${CHECK_FLAGS[@]}" 2>/dev/null)"
ACC="$ACC" FG="$FG" DIM="$DIM" OK="$OK" RST="$RST" COLS="$COLS" python3 - "$PENDING" <<'PY'
import json, os, sys

ACC, FG, DIM, OK, RST = (os.environ.get(k, "") for k in ("ACC", "FG", "DIM", "OK", "RST"))
cols = int(os.environ.get("COLS", "80"))
try:
    d = json.loads((sys.argv[1] if len(sys.argv) > 1 else "").strip() or "{}")
except Exception:
    d = {}

total = d.get("total", 0)
if not total:
    print(f"  {OK}Everything is already up to date.{RST}")
    print()
    sys.exit(0)

parts = [f"{n} {lbl}" for lbl, n in
         (("repo", d.get("repo", 0)), ("AUR", d.get("aur", 0)), ("flatpak", d.get("flatpak", 0))) if n]
print(f"  {FG}{total} package{'s' if total != 1 else ''}{RST}  {DIM}{' · '.join(parts)}{RST}\n")

# "name 1.2.3 -> 1.2.4" → aligned columns; the arrow is what the eye scans for, so the columns are
# sized from the DATA and then capped — gcc-style versions ("16.1.1+r581+gb73…-1") would otherwise
# shove the arrow off to the right and leave a ragged mess.
rows = []
for line in d.get("list", []):
    f = str(line).split()
    name = f[0] if f else str(line)
    old  = f[1] if len(f) > 1 else ""
    new  = f[3] if len(f) > 3 else (f[-1] if len(f) > 2 else "")
    rows.append((name, old, new))

shown = rows[:24]
def clip(s, w):
    return s if len(s) <= w else s[:w - 1] + "…"

avail = max(40, cols - 6)
namew = min(max((len(r[0]) for r in shown), default=12), 30)
oldw  = min(max((len(r[1]) for r in shown), default=8),  18, max(8, (avail - namew - 5) // 2))
neww  = max(8, avail - namew - oldw - 5)
for name, old, new in shown:
    print(f"   {FG}{clip(name, namew):<{namew}}{RST}  "
          f"{DIM}{clip(old, oldw):>{oldw}}{RST} {ACC}→{RST} {FG}{clip(new, neww)}{RST}")
rest = total - len(shown)
if rest > 0:
    print(f"   {DIM}+ {rest} more{RST}")
print()
PY
rule

# ── Run it ───────────────────────────────────────────────────────────────────────────────────────
# sudo's own prompt, in the palette — the password line is the first thing you see, so it should not
# look like it escaped from a different program.
export SUDO_PROMPT="$(printf '  %sadministrator password%s %s▸%s ' "$DIM" "$RST" "$ACC" "$RST")"

start=$SECONDS
printf '  %s%s%s\n\n' "$DIM" "$CMD" "$RST"
bash -lc "$CMD"
status=$?
took=$((SECONDS - start))

printf '\n'
rule
if [[ $status -eq 0 ]]; then
    printf '  %sdone%s  %sin %dm %02ds%s\n' "$OK" "$RST" "$DIM" "$((took / 60))" "$((took % 60))" "$RST"
else
    printf '  %sstopped (exit %d)%s  %safter %dm %02ds%s\n' "$ACC" "$status" "$RST" "$DIM" "$((took / 60))" "$((took % 60))" "$RST"
fi
printf '  %spress any key to close%s' "$DIM" "$RST"
read -rn1 -s
printf '\n'
