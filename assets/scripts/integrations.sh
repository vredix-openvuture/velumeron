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

# ── Neovim ─────────────────────────────────────────────────────────────────
# Two files, both ours, both in places a stock Neovim already reads: a real
# colours/ scheme (so `:colorscheme velumeron` works in ANY config, plugin
# manager or not) and an after/plugin hook that selects it at the end of startup.
# Neither replaces anything a user is likely to have, so this is a clean
# symlink+backup pair like the terminals.
NVIM_COLORS="$CFG/nvim/colors/velumeron.lua"
NVIM_HOOK="$CFG/nvim/after/plugin/velumeron-wallust.lua"

# ── Obsidian ───────────────────────────────────────────────────────────────
# The only integration whose target is not at a fixed path: a vault lives wherever the user put it,
# and there are usually several. Obsidian keeps the list itself, so we ask it rather than inventing
# a setting; which vault we actually enabled for is then remembered in a marker file, so `status`
# stays a question about the filesystem like every other tool here.
OBS_REGISTRY="$CFG/obsidian/obsidian.json"
OBS_VAULT_FILE="$STATE_DIR/obsidian-vault"
OBS_SNIPPET="$STATE_DIR/obsidian/wallust-colors.css"
OBS_SNIPPET_NAME="wallust-colors"
# The theme that actually consumes the --wl-* variables the snippet publishes.
OBS_THEME="Nexus"

# ── Terminal emulators ──────────────────────────────────────────────────────
# The terminal used to be kitty, hardcoded, with a velumeron kitty.conf living in the user dir and
# a wallust template writing colours next to it. That made ONE emulator a dependency of the desktop
# for no reason other than history. It is now a family of ordinary integrations: pick the one you
# actually use (or several), and the shell's terminal ROLE (hypr.lua `terminal`) is a separate
# choice that no longer implies any theming at all.
#
# One row per emulator: "<name>|<binary>|<target config>|<base file>". The base carries the shape
# (padding, opacity, bell) and a @VELUMERON_COLORS@ line; the renderer fills that in from the live
# palette, so a theme change re-renders every enabled terminal.
TERMINALS=(
    "kitty|kitty|$CFG/kitty/kitty.conf|kitty.conf.base"
    "alacritty|alacritty|$CFG/alacritty/alacritty.toml|alacritty.toml.base"
    "foot|foot|$CFG/foot/foot.ini|foot.ini.base"
    "wezterm|wezterm|$CFG/wezterm/wezterm.lua|wezterm.lua.base"
    "ghostty|ghostty|$CFG/ghostty/config|ghostty.base"
)
term_field() { local IFS='|'; read -r -a f <<< "$1"; printf '%s' "${f[$2]}"; }
term_row() {  # $1 name → the row, or empty
    local r
    for r in "${TERMINALS[@]}"; do [[ "$(term_field "$r" 0)" == "$1" ]] && { printf '%s' "$r"; return; }; done
}

# ── Marker-file state, for integrations that own no config of their own ─────
# pywalfox has nothing at a fixed path to look at: it reads a cache we write. So "is it on" is a
# question only we can answer, and it is answered by a file we drop here.
FLAG_DIR="$STATE_DIR/enabled"
st_flag()  { [[ -e "$FLAG_DIR/$1" ]] && echo on || echo off; }
flag_on()  { mkdir -p "$FLAG_DIR"; : > "$FLAG_DIR/$1"; }
flag_off() { rm -f "$FLAG_DIR/$1"; }

# pywal drop-in — what pywalfox (and every other pywal-shaped tool) reads.
WAL_COLORS="$CACHE/wal/colors"
WAL_JSON="$CACHE/wal/colors.json"

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
build_nvim() {
    mkdir -p "$STATE_DIR/nvim"
    # Rendered to a temp file and moved into place: the target is what a running
    # nvim re-reads on `colorscheme velumeron`, and a plain redirect would leave
    # it truncated for the length of the render. mv on the same filesystem is
    # atomic, so an instance either reads the old scheme or the new one.
    $RENDER nvim > "$STATE_DIR/nvim/velumeron.lua.tmp"
    mv -f "$STATE_DIR/nvim/velumeron.lua.tmp" "$STATE_DIR/nvim/velumeron.lua"
    cp -f "$SRC_DIR/nvim/velumeron-wallust.lua" "$STATE_DIR/nvim/velumeron-wallust.lua"
}
build_terminal() {   # $1 name — base config + freshly rendered colours → managed file
    local row base out
    row="$(term_row "$1")"; [[ -n "$row" ]] || return 1
    base="$SRC_DIR/terminals/$(term_field "$row" 3)"
    out="$STATE_DIR/terminals/$(basename "$(term_field "$row" 2)")"
    mkdir -p "$STATE_DIR/terminals"
    # Substituted in python, not sed: the colour block is multi-line and full of characters
    # (&, #, /) that sed would either eat or need escaping for.
    $RENDER "term-$1" | python3 -c '
import sys
base, out = sys.argv[1], sys.argv[2]
sys.stdout = open(out, "w")
sys.stdout.write(open(base).read().replace("@VELUMERON_COLORS@", sys.stdin.read().rstrip("\n")))
' "$base" "$out"
}
# A running Neovim re-reads the scheme when it is told to select it again. The
# server socket every instance opens by default is how we reach one without
# touching its input: --remote-expr evaluates in the remote instance and leaves
# the mode, the cursor and any half-typed line exactly where they were.
reload_nvim() {
    command -v nvim >/dev/null 2>&1 || return 0
    local sock
    for sock in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/nvim.*; do
        [[ -S "$sock" ]] || continue
        nvim --server "$sock" --remote-expr \
             'execute("silent! colorscheme velumeron")' >/dev/null 2>&1 || true
    done
}
build_pywal() {
    mkdir -p "$(dirname "$WAL_COLORS")"
    $RENDER pywal-colors > "$WAL_COLORS"
    $RENDER pywal-json   > "$WAL_JSON"
}
build_obsidian() {
    mkdir -p "$(dirname "$OBS_SNIPPET")"
    $RENDER obsidian > "$OBS_SNIPPET"
}

# ── Obsidian helpers ────────────────────────────────────────────────────────
# Every vault Obsidian knows about, one path per line, the currently open one first (that is the
# one a "just switch it on" almost always means). Silent on a machine without Obsidian.
obs_vaults() {
    [[ -f "$OBS_REGISTRY" ]] || return 0
    python3 - "$OBS_REGISTRY" <<'PY' 2>/dev/null || true
import json, os, sys
try:
    vaults = (json.load(open(sys.argv[1])) or {}).get("vaults") or {}
except (OSError, ValueError):
    sys.exit(0)
rows = [v for v in vaults.values() if isinstance(v, dict) and v.get("path")]
rows.sort(key=lambda v: (not v.get("open"), -(v.get("ts") or 0)))
for v in rows:
    if os.path.isdir(v["path"]):
        print(v["path"])
PY
}
# Which vault to act on with no argument. The open one, or the only one — never a guess between
# several closed vaults, because writing a snippet into the wrong notes is not a small mistake.
obs_pick() {
    local -a v; mapfile -t v < <(obs_vaults)
    if (( ${#v[@]} == 0 )); then return 1; fi
    printf '%s' "${v[0]}"
}
# The vault we are actually enabled for, from the marker. Empty if off or if the vault is gone.
obs_vault() {
    if [[ -f "$OBS_VAULT_FILE" ]]; then
        local p; p="$(<"$OBS_VAULT_FILE")"
        if [[ -d "$p" ]]; then printf '%s' "$p"; fi
    fi
    return 0
}
obs_target() { printf '%s/.obsidian/snippets/%s.css' "$1" "$OBS_SNIPPET_NAME"; }
# Add or remove our snippet in a vault's enabledCssSnippets. Surgical on purpose: appearance.json
# also holds the theme, the fonts and the accent colour, all of which the user changes from
# Obsidian's own settings. Restoring a backup taken when the integration was switched on would
# quietly undo those. The backup is still taken, as a safety net, but the reversal is this.
obs_snippet_enabled() {  # $1 vault, $2 on|off
    python3 - "$1/.obsidian/appearance.json" "$OBS_SNIPPET_NAME" "$2" <<'PY' 2>/dev/null || true
import json, os, sys
path, name, want = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    d = json.load(open(path)) if os.path.exists(path) else {}
except (OSError, ValueError):
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
lst = d.get("enabledCssSnippets")
lst = list(lst) if isinstance(lst, list) else []
if want == "on" and name not in lst:
    lst.append(name)
elif want == "off":
    lst = [x for x in lst if x != name]
d["enabledCssSnippets"] = lst
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)
PY
}
obs_has_theme() { [[ -d "$1/.obsidian/themes/$OBS_THEME" ]]; }

# ── per-tool status / enable / disable ──────────────────────────────────────
st_fastfetch() { is_ours "$FF_TARGET"   && echo on || { [[ -e "$FF_TARGET"   || -L "$FF_TARGET"   ]] && echo foreign || echo off; }; }
st_starship()  { is_ours "$SS_TARGET"   && echo on || { [[ -e "$SS_TARGET"   || -L "$SS_TARGET"   ]] && echo foreign || echo off; }; }
st_cava()      { is_ours "$CAVA_TARGET" && echo on || { [[ -e "$CAVA_TARGET" || -L "$CAVA_TARGET" ]] && echo foreign || echo off; }; }
st_btop()      { [[ "$($EDIT kv-get   "$BTOP_CONF" color_theme)" == "velumeron" ]] && echo on || echo off; }
st_spotify()   { [[ "$($EDIT kv-get   "$SPOT_APP"  theme)"       == "velumeron" ]] && echo on || echo off; }
st_codium()    { [[ "$($EDIT json-get "$CODIUM_SETTINGS" workbench.colorTheme)" == "$CODIUM_THEME_LABEL" ]] && echo on || echo off; }
# The scheme file is the one that decides: the hook is worthless without it.
st_nvim()      { is_ours "$NVIM_COLORS" && echo on || { [[ -e "$NVIM_COLORS" || -L "$NVIM_COLORS" ]] && echo foreign || echo off; }; }

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

en_nvim() {
    build_nvim
    link_in "$NVIM_COLORS" "$STATE_DIR/nvim/velumeron.lua"
    link_in "$NVIM_HOOK"   "$STATE_DIR/nvim/velumeron-wallust.lua"
}

dis_fastfetch() { unlink_out "$FF_TARGET"; }
dis_starship()  { unlink_out "$SS_TARGET"; }
dis_cava()      { unlink_out "$CAVA_TARGET"; }
dis_btop()      { restore_bak "$BTOP_CONF"; rm -f "$BTOP_THEME"; }
dis_spotify()   { restore_bak "$SPOT_APP"; restore_bak "$SPOT_THEME"; }
dis_codium()    { restore_bak "$CODIUM_SETTINGS"; rm -rf "$CODIUM_EXT"; }
dis_nvim()      { unlink_out "$NVIM_COLORS"; unlink_out "$NVIM_HOOK"; }

# ── Terminals: symlink+backup, exactly like fastfetch/starship/cava ─────────
st_term() {   # $1 name
    local t; t="$(term_field "$(term_row "$1")" 2)"
    is_ours "$t" && echo on || { [[ -e "$t" || -L "$t" ]] && echo foreign || echo off; }
}
en_term() {   # $1 name
    local t; t="$(term_field "$(term_row "$1")" 2)"
    build_terminal "$1"
    link_in "$t" "$STATE_DIR/terminals/$(basename "$t")"
}
dis_term() { unlink_out "$(term_field "$(term_row "$1")" 2)"; }

# ── pywalfox: we write the pywal cache, pywalfox reads it ──────────────────
# Enabling does NOT install or configure pywalfox — that is `pywalfox install` once, in the browser.
# What this owns is the palette handover: the two ~/.cache/wal files, refreshed on every theme
# change, plus the `pywalfox update` push so an open browser recolours without a restart.
st_pywalfox()  { st_flag pywalfox; }
en_pywalfox()  {
    backup_once "$WAL_COLORS"; backup_once "$WAL_JSON"
    build_pywal; flag_on pywalfox
    command -v pywalfox >/dev/null 2>&1 && pywalfox update >/dev/null 2>&1 || true
}
dis_pywalfox() { flag_off pywalfox; restore_bak "$WAL_COLORS"; restore_bak "$WAL_JSON"; }

# ── Obsidian: a CSS snippet in the vault, enabled in the vault's appearance ─
# What this hands over is a palette, not a look: the snippet only defines --wl-* custom properties.
# A theme that reads them (Nexus does) recolours with the wallpaper; any other theme is untouched,
# which is why switching this on can never ruin a vault's appearance.
st_obsidian() {
    local v; v="$(obs_vault)"
    if [[ -z "$v" ]]; then echo off; return 0; fi
    local t; t="$(obs_target "$v")"
    is_ours "$t" && echo on || { [[ -e "$t" || -L "$t" ]] && echo foreign || echo off; }
}
en_obsidian() {   # $1 vault path, optional
    local v="${1:-}"
    [[ -n "$v" ]] || v="$(obs_pick || true)"
    if [[ -z "$v" || ! -d "$v" ]]; then
        echo "obsidian: no vault found — open one in Obsidian once, or pass its path" >&2
        return 2
    fi
    build_obsidian
    link_in "$(obs_target "$v")" "$OBS_SNIPPET"
    backup_once "$v/.obsidian/appearance.json"
    obs_snippet_enabled "$v" on
    mkdir -p "$(dirname "$OBS_VAULT_FILE")"
    printf '%s\n' "$v" > "$OBS_VAULT_FILE"
    obs_has_theme "$v" || echo "obsidian: the $OBS_THEME theme is not installed in this vault — the palette is published but nothing reads it yet" >&2
}
dis_obsidian() {
    local v; v="$(obs_vault)"
    if [[ -n "$v" ]]; then
        unlink_out "$(obs_target "$v")"
        obs_snippet_enabled "$v" off
    fi
    rm -f "$OBS_VAULT_FILE"
}

TOOLS=(fastfetch starship cava btop spotify codium nvim pywalfox obsidian)

# ── dispatch ────────────────────────────────────────────────────────────────
# Terminals are addressed as "term-<name>" so ONE namespace covers every integration and the
# panel needs no second command to drive them.
cmd="${1:-status}"; name="${2:-}"
is_term()   { [[ "$1" == term-* ]] && [[ -n "$(term_row "${1#term-}")" ]]; }
is_tool()   { case " ${TOOLS[*]} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

case "$cmd" in
    status)
        sep=""; printf '{'
        for t in "${TOOLS[@]}"; do printf '%s"%s":"%s"' "$sep" "$t" "$(st_$t)"; sep=","; done
        for r in "${TERMINALS[@]}"; do
            printf '%s"term-%s":"%s"' "$sep" "$(term_field "$r" 0)" "$(st_term "$(term_field "$r" 0)")"
        done
        # Which emulators this machine actually has. A row for a terminal that is not installed is
        # still worth showing (it says what velumeron CAN theme) but must not offer a switch that
        # would only write a config nobody reads.
        printf '%s"installed":{' "$sep"; sep=""
        for r in "${TERMINALS[@]}"; do
            command -v "$(term_field "$r" 1)" >/dev/null 2>&1 && v=true || v=false
            printf '%s"%s":%s' "$sep" "$(term_field "$r" 0)" "$v"; sep=","
        done
        command -v pywalfox >/dev/null 2>&1 && v=true || v=false
        printf ',"pywalfox":%s' "$v"
        command -v nvim >/dev/null 2>&1 && v=true || v=false
        printf ',"nvim":%s' "$v"
        # Obsidian counts as installed once it knows about at least one vault, because that is the
        # only thing this integration needs. The detail below says which vault it is pointed at and
        # whether the theme that reads the palette is actually there.
        obs_n=$(obs_vaults | grep -c '' || true)
        [[ "$obs_n" -gt 0 ]] && v=true || v=false
        printf ',"obsidian":%s}' "$v"
        obs_v="$(obs_vault)"; [[ -n "$obs_v" ]] || obs_v="$(obs_pick || true)"
        [[ -n "$obs_v" ]] && obs_has_theme "$obs_v" && v=true || v=false
        # A DIFFERENT key from the "obsidian" switch above. JSON tolerates a duplicate key and the
        # parser simply keeps the last one, so reusing the name would silently replace the on/off
        # state with this object.
        printf ',"obsidian_detail":{"vaults":%s,"vault":"%s","theme":%s,"theme_name":"%s"}}\n' \
               "$obs_n" "${obs_v//\"/}" "$v" "$OBS_THEME"
        ;;
    vaults)   # every vault Obsidian knows about, for the panel's picker. Open one first.
        sep=""; printf '['
        while IFS= read -r p; do
            [[ -n "$p" ]] || continue
            printf '%s{"path":"%s","name":"%s","theme":%s}' \
                   "$sep" "${p//\"/}" "$(basename "${p//\"/}")" \
                   "$(obs_has_theme "$p" && echo true || echo false)"
            sep=","
        done < <(obs_vaults)
        printf ']\n'
        ;;
    enable)
        # Obsidian takes an optional third argument: which vault. Everything else ignores it.
        if   is_term "$name"; then en_term "${name#term-}"
        elif [[ "$name" == obsidian ]]; then en_obsidian "${3:-}"
        elif is_tool "$name"; then en_$name
        else echo "unknown: $name" >&2; exit 2; fi ;;
    disable)
        if   is_term "$name"; then dis_term "${name#term-}"
        elif is_tool "$name"; then dis_$name
        else echo "unknown: $name" >&2; exit 2; fi ;;
    refresh)   # re-theme hook: rebuild only what's currently active
        [[ "$(st_starship)" == on ]] && build_starship || true
        [[ "$(st_cava)"     == on ]] && build_cava     || true
        [[ "$(st_btop)"     == on ]] && build_btop_theme || true
        [[ "$(st_codium)"   == on ]] && build_codium_theme || true
        if [[ "$(st_nvim)" == on ]]; then { build_nvim && reload_nvim; } || true; fi
        if [[ "$(st_spotify)" == on ]]; then $RENDER spotify-theme | $EDIT block-set "$SPOT_THEME"; fi
        # Terminals re-render in place: the target is a symlink to the managed file, so a running
        # emulator that reloads its config (kitty SIGUSR1, foot SIGUSR1) picks it up with no restart.
        for r in "${TERMINALS[@]}"; do
            t="$(term_field "$r" 0)"
            [[ "$(st_term "$t")" == on ]] && build_terminal "$t" || true
        done
        pkill -USR1 -x kitty >/dev/null 2>&1 || true
        pkill -USR1 -x foot  >/dev/null 2>&1 || true
        if [[ "$(st_pywalfox)" == on ]]; then
            build_pywal
            command -v pywalfox >/dev/null 2>&1 && pywalfox update >/dev/null 2>&1 || true
        fi
        # Obsidian: rewriting the managed snippet is the whole refresh. The vault's copy is a
        # symlink to it and Obsidian reloads snippets by itself, so an open vault recolours live.
        [[ "$(st_obsidian)" == on ]] && build_obsidian || true
        ;;
    *)
        echo "usage: integrations.sh {status | vaults | enable <name> [vault] | disable <name> | refresh}" >&2; exit 2 ;;
esac
