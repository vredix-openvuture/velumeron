#!/usr/bin/env bash
# boot-theme-run.sh <component> <theme>
#
# The terminal session behind Settings → Boot & Login. Switching a boot theme is the
# one Velumeron action that genuinely needs root — it writes /etc, /usr/share and
# rebuilds the initramfs or grub.cfg — and it is slow enough to want a progress view.
# So it gets the same treatment the bar's Updates module gets: the banner, what is
# about to happen spelled out in the live palette, a framed sudo prompt, and the real
# command's own output underneath.
#
# Nothing is hidden: the exact boot-theme.py invocation is printed before it runs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

COMP="${1:-}"
THEME="${2:-}"
if [[ -z "$COMP" || -z "$THEME" ]]; then
    echo "usage: boot-theme-run.sh <plymouth|grub|sddm> <theme>" >&2
    exit 1
fi

# ── Palette → 24-bit ANSI (same role mapping as update-run.sh / the shell) ───────────────────────
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

print("ACC=$'%s'" % (esc(c.get("color3"), True)                    or "\\033[1;36m"))
print("FG=$'%s'"  % (esc(c.get("color7") or c.get("foreground"))   or "\\033[0m"))
print("DIM=$'%s'" % (esc(c.get("color8"))                          or "\\033[2m"))
print("OK=$'%s'"  % (esc(c.get("color15") or c.get("foreground"), True) or "\\033[1m"))
PY
)"
RST=$'\033[0m'
COLS=$(tput cols 2>/dev/null || echo 80)
rep()  { local n=$1 c=$2 s='' i; for ((i = 0; i < n; i++)); do s+="$c"; done; printf '%s' "$s"; }
rule() { printf '  %s%s%s\n' "$DIM" "$(rep $((COLS - 4)) '─')" "$RST"; }

BANNER="$VELUMERON_DIR/assets/icons/velumeron_banner-white.png"
banner_text() {
    local word='V E L U M E R O N'
    local w=$(( COLS > 46 ? 42 : COLS - 6 ))
    local pad=$(( (w - ${#word}) / 2 ))
    printf '\n  %s╭%s╮%s\n' "$DIM" "$(rep "$w" '─')" "$RST"
    printf '  %s│%s%s%s%s%s│%s\n' "$DIM" "$RST" "$(rep "$pad" ' ')" \
           "$ACC$word$RST" "$(rep $(( w - ${#word} - pad )) ' ')" "$DIM" "$RST"
    printf '  %s╰%s╯%s\n\n' "$DIM" "$(rep "$w" '─')" "$RST"
}
banner() {
    [[ -f "$BANNER" ]] || { banner_text; return; }
    if [[ -n "${KITTY_WINDOW_ID:-}" || "${TERM:-}" == xterm-kitty* ]] && command -v kitten >/dev/null 2>&1; then
        local rows=8
        if kitten icat --align center --place "${COLS}x${rows}@0x1" "$BANNER" 2>/dev/null; then
            tput cup $((rows + 2)) 0 2>/dev/null || printf '\n'
            return
        fi
    fi
    if command -v chafa >/dev/null 2>&1; then
        printf '\n'
        chafa --size "$((COLS - 4))x9" --align center "$BANNER" 2>/dev/null && { printf '\n'; return; }
    fi
    banner_text
}
clear
banner

# ── What is about to happen ─────────────────────────────────────────────────────────────────────
# Each component pays a different price for a theme switch; saying so up front is the difference
# between "it hung" and "it is rebuilding the initramfs, that takes a moment".
case "$COMP" in
    plymouth) LABEL="Plymouth · boot splash"
              STEPS=("write /etc/plymouth/plymouthd.conf" "rebuild the initramfs (mkinitcpio -P)")
              SLOW="the initramfs rebuild takes ~10–60s" ;;
    grub)     LABEL="GRUB · boot menu"
              STEPS=("set GRUB_THEME in /etc/default/grub" "regenerate grub.cfg (grub-mkconfig)")
              SLOW="grub-mkconfig probes every disk — a few seconds" ;;
    sddm)     LABEL="SDDM · login screen"
              STEPS=("write /etc/sddm.conf.d/zz-velumeron.conf")
              SLOW="takes effect at the next login screen" ;;
    *)        LABEL="$COMP"; STEPS=("apply the theme"); SLOW="" ;;
esac

printf '  %sBOOT THEME%s\n' "$ACC" "$RST"
rule
printf '  %s%s%s\n' "$FG" "$LABEL" "$RST"
printf '  %stheme%s  %s%s%s\n\n' "$DIM" "$RST" "$OK" "$THEME" "$RST"
for s in "${STEPS[@]}"; do
    printf '   %s·%s %s%s%s\n' "$ACC" "$RST" "$FG" "$s" "$RST"
done
[[ -n "$SLOW" ]] && printf '\n  %s%s%s\n' "$DIM" "$SLOW" "$RST"
printf '\n'
rule

# ── Run it ──────────────────────────────────────────────────────────────────────────────────────
export SUDO_PROMPT="$(printf '  %sadministrator password%s %s▸%s ' "$DIM" "$RST" "$ACC" "$RST")"

# No `sudo -E`: with the default `Defaults env_reset` sudoers and no SETENV tag, -E
# does not merely fail to preserve the environment — it refuses to run at all. It is
# not needed either: boot-theme.py derives VELUMERON_DIR from its own resolved path
# and re-anchors the user dirs from $SUDO_USER, which sudo always sets.
CMD=(sudo python3 "$VELUMERON_DIR/assets/scripts/boot-theme.py" apply "$COMP" "$THEME")
printf '  %s%s%s\n\n' "$DIM" "${CMD[*]}" "$RST"

start=$SECONDS
"${CMD[@]}"
status=$?
took=$((SECONDS - start))

printf '\n'
rule
if [[ $status -eq 0 ]]; then
    printf '  %sapplied%s  %sin %dm %02ds%s\n' "$OK" "$RST" "$DIM" "$((took / 60))" "$((took % 60))" "$RST"
    case "$COMP" in
        plymouth) printf '  %svisible on the next boot%s\n' "$DIM" "$RST" ;;
        grub)     printf '  %svisible on the next boot%s\n' "$DIM" "$RST" ;;
        sddm)     printf '  %svisible on the next login screen%s\n' "$DIM" "$RST" ;;
    esac
else
    printf '  %sstopped (exit %d)%s  %safter %dm %02ds%s\n' "$ACC" "$status" "$RST" "$DIM" "$((took / 60))" "$((took % 60))" "$RST"
fi
printf '  %spress any key to close%s' "$DIM" "$RST"
read -rn1 -s
printf '\n'
exit $status
