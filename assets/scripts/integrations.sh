#!/usr/bin/env bash
# ── Velumeron integrations ─────────────────────────────────────────────────
# Reversible enable/disable of velumeron-styled shell tools. Driven by the
# Settings → Integrations panel.
#
# PROMISE: a user's own config is NEVER destroyed. Two reversible mechanisms:
#
#   • symlink+backup (fastfetch, starship, cava): a real config at the target is
#     moved to "<target>.velumeron-bak" (an existing backup is never clobbered)
#     and the target becomes a symlink into our managed configs. Disable removes
#     OUR symlink and restores the backup. A target that isn't our symlink is
#     reported "foreign" and left untouched.
#
#   • key/block edit + backup (btop, spotify, codium): the tool's own config is
#     copied to "<file>.velumeron-bak" (once), then ONE selection key is flipped
#     (and, for spotify, one marker-delimited theme block appended) in place —
#     everything else in the file is preserved. Disable restores the byte-exact
#     backup. Extra assets (btop theme file, codium extension) are additive and
#     removed on disable.
#
# Colour-following tools are rebuilt from the live wallust palette (colors.json)
# on every theme change via the `refresh` subcommand (wallust hook).
#
# Usage: integrations.sh {status | enable <name> | disable <name> | refresh}
set -euo pipefail

# Resolve through the ~/.config/velumeron/assets/scripts symlink (readlink -f) so
# the fallback lands in the real repo/package tree even when the env var is unset.
_self="$(readlink -f "${BASH_SOURCE[0]}")"
VELUMERON_DIR="${VELUMERON_DIR:-$(cd "$(dirname "$_self")/../.." && pwd)}"
SCRIPTS="$VELUMERON_DIR/assets/scripts"
RENDER="python3 $SCRIPTS/integrations-render.py"
EDIT="python3 $SCRIPTS/integrations-edit.py"

SRC_DIR="$VELUMERON_DIR/integrations"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_DIR="$CFG/velumeron/integrations"          # our managed configs live here

# Targets
FF_TARGET="$CFG/fastfetch/config.jsonc"
SS_TARGET="$CFG/starship.toml"
CAVA_TARGET="$CFG/cava/config"
BTOP_CONF="$CFG/btop/btop.conf"
BTOP_THEME="$CFG/btop/themes/velumeron.theme"
SPOT_APP="$CFG/spotify-player/app.toml"
SPOT_THEME="$CFG/spotify-player/theme.toml"
CODIUM_SETTINGS="$CFG/VSCodium/User/settings.json"
CODIUM_EXT="$HOME/.vscode-oss/extensions/velumeron-wallust-theme"
CODIUM_THEME_LABEL="Velumeron Wallust"

# ── generic helpers ────────────────────────────────────────────────────────
is_ours() {   # symlink resolving into our state dir?
    [[ -L "$1" ]] || return 1
    case "$(readlink -f "$1" 2>/dev/null || true)" in
        "$STATE_DIR"/*) return 0 ;; *) return 1 ;;
    esac
}
link_in() {   # $1 target, $2 managed
    local t="$1" m="$2" bak
    mkdir -p "$(dirname "$t")"
    if is_ours "$t"; then ln -sfn "$m" "$t"; return; fi
    if [[ -e "$t" || -L "$t" ]]; then
        bak="$t.velumeron-bak"
        [[ -e "$bak" || -L "$bak" ]] && bak="$t.velumeron-bak.$(date +%s)"
        mv "$t" "$bak"
    fi
    ln -sfn "$m" "$t"
}
unlink_out() {  # $1 target — only our own symlink; restore pristine backup
    local t="$1" bak="$1.velumeron-bak"
    is_ours "$t" || return 0
    rm -f "$t"
    [[ -e "$bak" || -L "$bak" ]] && mv "$bak" "$t"
    return 0
}
backup_once() { # copy a real file aside exactly once (keeps the pristine original)
    local f="$1" bak="$1.velumeron-bak"
    [[ -e "$f" ]] || return 0
    [[ -e "$bak" || -L "$bak" ]] || cp -a "$f" "$bak"
    return 0
}
restore_bak() { # put the pristine original back
    local f="$1" bak="$1.velumeron-bak"
    [[ -e "$bak" || -L "$bak" ]] && mv -f "$bak" "$f"
    return 0
}

# ── builders (regenerate managed / themed files from the current palette) ───
build_fastfetch() {
    mkdir -p "$STATE_DIR/fastfetch"
    local cfg="$STATE_DIR/fastfetch/config.jsonc" art="$STATE_DIR/fastfetch/raven.txt"
    cp -f "$SRC_DIR/fastfetch/config.jsonc" "$cfg"
    # Downscale the plain raven SHAPE (drawn large & comfortable in raven.txt) to
    # compact Unicode block art in the terminal's magenta (wallust-themed, so the
    # logo follows the wallpaper). RAVEN_FACTOR=1 → half size, 2 → quarter, …
    $RENDER raven "$SRC_DIR/fastfetch/raven.txt" "${RAVEN_FACTOR:-1}" > "$art"

    # Centre the logo beside the stats. Vertically: pad the raven down by half the
    # difference to the info-column height. Horizontally: fastfetch left-pads the
    # logo, so nudge padding-left so the (dedented) raven sits centred in the gap
    # to the stats. Both are baked into the generated logo so the config stays
    # static. Emitted as raw ANSI; config logo type is "file-raw".
    local rh iw rw ih vpad
    rh=$(grep -c '' "$art")
    rw=$(sed 's/\x1b\[[0-9;]*m//g' "$art" | awk '{ n=0; for(i=1;i<=length($0);i++) if(substr($0,i,1)!=" ") n=i; if(n>m) m=n } END{ print m+0 }')
    ih=$(fastfetch --config "$cfg" --logo none 2>/dev/null | grep -c '')
    vpad=$(( (ih - rh) / 2 )); (( vpad < 0 )) && vpad=0
    { for ((i=0; i<vpad; i++)); do echo; done; cat "$art"; } > "$art.tmp" && mv "$art.tmp" "$art"

    # horizontal: centre the raven within a fixed logo band (~28 cols) via left pad
    local band=28 hpad
    hpad=$(( (band - rw) / 2 )); (( hpad < 2 )) && hpad=2
    python3 -c "import json,sys,re; s=re.sub(r'^\s*//.*$','',open('$cfg').read(),flags=re.M); d=json.loads(s); d['logo']['padding']['left']=$hpad; d['logo']['padding'].pop('top',None); json.dump(d,open('$cfg','w'),indent=4)"
}
build_starship() {
    mkdir -p "$STATE_DIR"
    # Base (Pastel Powerline shape) + the [palettes.velumeron] block rendered
    # from the live palette. The palette is named "velumeron" — NOT "noctalia" —
    # so the shell's own merge (velumeron's fish config cats a [palettes.noctalia]
    # block onto this file) adds a *different* table and can never duplicate a
    # key. Strip any stray palette table from the base defensively.
    {
        awk '/^\[palettes\./{exit} {print}' "$SRC_DIR/starship/starship.toml"
        echo
        $RENDER starship-palette
    } > "$STATE_DIR/starship.toml"
}
build_cava() {
    mkdir -p "$STATE_DIR/cava"
    { cat "$SRC_DIR/cava/config.base"; echo; $RENDER cava; } > "$STATE_DIR/cava/config"
}
build_btop_theme() {
    mkdir -p "$(dirname "$BTOP_THEME")"
    $RENDER btop > "$BTOP_THEME"
}
build_codium_theme() {
    mkdir -p "$CODIUM_EXT/themes"
    cp -f "$SRC_DIR/codium/package.json" "$CODIUM_EXT/package.json"
    $RENDER codium > "$CODIUM_EXT/themes/velumeron-color-theme.json"
}

# ── per-tool status / enable / disable ──────────────────────────────────────
st_fastfetch() { is_ours "$FF_TARGET"   && echo on || { [[ -e "$FF_TARGET"   || -L "$FF_TARGET"   ]] && echo foreign || echo off; }; }
st_starship()  { is_ours "$SS_TARGET"   && echo on || { [[ -e "$SS_TARGET"   || -L "$SS_TARGET"   ]] && echo foreign || echo off; }; }
st_cava()      { is_ours "$CAVA_TARGET" && echo on || { [[ -e "$CAVA_TARGET" || -L "$CAVA_TARGET" ]] && echo foreign || echo off; }; }
st_btop()      { [[ "$($EDIT kv-get   "$BTOP_CONF" color_theme)" == "velumeron" ]] && echo on || echo off; }
st_spotify()   { [[ "$($EDIT kv-get   "$SPOT_APP"  theme)"       == "velumeron" ]] && echo on || echo off; }
st_codium()    { [[ "$($EDIT json-get "$CODIUM_SETTINGS" workbench.colorTheme)" == "$CODIUM_THEME_LABEL" ]] && echo on || echo off; }

en_fastfetch() { build_fastfetch; link_in "$FF_TARGET"   "$STATE_DIR/fastfetch/config.jsonc"; }
en_starship()  { build_starship;  link_in "$SS_TARGET"   "$STATE_DIR/starship.toml"; }
en_cava()      { build_cava;      link_in "$CAVA_TARGET" "$STATE_DIR/cava/config"; }
en_btop() {
    [[ -f "$BTOP_CONF" ]] || { mkdir -p "$(dirname "$BTOP_CONF")"; printf 'color_theme = "Default"\n' > "$BTOP_CONF"; }
    backup_once "$BTOP_CONF"; build_btop_theme; $EDIT kv-set "$BTOP_CONF" color_theme velumeron
}
en_spotify() {
    [[ -f "$SPOT_APP" ]] || { mkdir -p "$(dirname "$SPOT_APP")"; printf 'theme = "default"\n' > "$SPOT_APP"; }
    backup_once "$SPOT_APP"; backup_once "$SPOT_THEME"
    $RENDER spotify-theme | $EDIT block-set "$SPOT_THEME"
    $EDIT kv-set "$SPOT_APP" theme velumeron
}
en_codium() {
    mkdir -p "$(dirname "$CODIUM_SETTINGS")"
    [[ -f "$CODIUM_SETTINGS" ]] || printf '{\n}\n' > "$CODIUM_SETTINGS"
    backup_once "$CODIUM_SETTINGS"; build_codium_theme
    $EDIT json-set "$CODIUM_SETTINGS" workbench.colorTheme "$CODIUM_THEME_LABEL"
}

dis_fastfetch() { unlink_out "$FF_TARGET"; }
dis_starship()  { unlink_out "$SS_TARGET"; }
dis_cava()      { unlink_out "$CAVA_TARGET"; }
dis_btop()      { restore_bak "$BTOP_CONF"; rm -f "$BTOP_THEME"; }
dis_spotify()   { restore_bak "$SPOT_APP"; restore_bak "$SPOT_THEME"; }
dis_codium()    { restore_bak "$CODIUM_SETTINGS"; rm -rf "$CODIUM_EXT"; }

TOOLS=(fastfetch starship cava btop spotify codium)

# ── dispatch ────────────────────────────────────────────────────────────────
cmd="${1:-status}"; name="${2:-}"
case "$cmd" in
    status)
        sep=""; printf '{'
        for t in "${TOOLS[@]}"; do printf '%s"%s":"%s"' "$sep" "$t" "$(st_$t)"; sep=","; done
        printf '}\n'
        ;;
    enable)
        case " ${TOOLS[*]} " in *" $name "*) en_$name ;; *) echo "unknown: $name" >&2; exit 2 ;; esac ;;
    disable)
        case " ${TOOLS[*]} " in *" $name "*) dis_$name ;; *) echo "unknown: $name" >&2; exit 2 ;; esac ;;
    refresh)   # re-theme hook: rebuild only what's currently active
        [[ "$(st_starship)" == on ]] && build_starship || true
        [[ "$(st_cava)"     == on ]] && build_cava     || true
        [[ "$(st_btop)"     == on ]] && build_btop_theme || true
        [[ "$(st_codium)"   == on ]] && build_codium_theme || true
        if [[ "$(st_spotify)" == on ]]; then $RENDER spotify-theme | $EDIT block-set "$SPOT_THEME"; fi
        ;;
    *)
        echo "usage: integrations.sh {status|enable <name>|disable <name>|refresh}" >&2; exit 2 ;;
esac
