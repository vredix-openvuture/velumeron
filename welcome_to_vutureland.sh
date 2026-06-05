#!/usr/bin/env bash
# Vutureland setup wizard.
#
#   welcome_to_vutureland.sh           Full interactive first-run setup
#   welcome_to_vutureland.sh --sync    Refresh package templates from
#                                      $VUTURELAND_DIR without touching user
#                                      state (use after a pacman/yay upgrade)

set -euo pipefail

# Detect the package dir from this script's own location (realpath resolves
# the /usr/bin/vutureland-setup symlink → /usr/share/vutureland/…). We trust
# a pre-set VUTURELAND_DIR env var only if it points at a real vutureland
# package — otherwise it would be a stale value from an older install and
# corrupt every path we write (e.g. into ~/.config/hypr/hyprland.lua).
_SELF_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
if [[ -z "${VUTURELAND_DIR:-}" \
   || ! -f "$VUTURELAND_DIR/bin/vutureland" \
   || ! -d "$VUTURELAND_DIR/hypr.lua/modules" ]]; then
    VUTURELAND_DIR="$_SELF_DIR"
fi
: "${VUTURELAND_USER_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/vutureland}"
export VUTURELAND_DIR VUTURELAND_USER_DIR

# Never run this script as root. It writes into the user's home and would
# end up owning ~/.config/vutureland/ as root, breaking every subsequent
# non-root run with permission-denied. Package installation (pacman/yay)
# uses sudo internally, but THIS wizard must run as the desktop user.
if [[ $EUID -eq 0 ]]; then
    echo ""
    echo "  vutureland-setup must NOT be run as root."
    echo "  Drop sudo and re-run as your desktop user:"
    echo ""
    echo "      vutureland-setup ${1:-}"
    echo ""
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo "  If files in your home are already owned by root, fix them:"
        echo "      sudo chown -R $SUDO_USER:$SUDO_USER \\"
        echo "          ~$SUDO_USER/.config/vutureland \\"
        echo "          ~$SUDO_USER/.config/hypr \\"
        echo "          ~$SUDO_USER/.config/wallust \\"
        echo "          ~$SUDO_USER/.config/environment.d"
        echo ""
    fi
    exit 1
fi
USER_SETTINGS="$VUTURELAND_USER_DIR/hypr.lua/user_settings.lua"

# Parse flags
SYNC_MODE=false
for arg in "$@"; do
    case "$arg" in
        --sync) SYNC_MODE=true ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--sync]"
            echo "  --sync   Refresh package templates without re-running setup"
            exit 0 ;;
    esac
done

BOLD=$'\033[1m'; CYAN=$'\033[0;36m'; GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; RST=$'\033[0m'; DIM=$'\033[2m'

ok()   { echo "  ${GREEN}✓${RST}  $*"; }
warn() { echo "  ${YELLOW}!${RST}  $*"; }
err()  { echo "  ${RED}✗${RST}  $*" >&2; }
say()  { echo ""; echo "  ${BOLD}${CYAN}── $*${RST}"; echo ""; }
hr()   { echo "  ──────────────────────────────────────────────────────────"; }

ask_yn() {
    local prompt="$1" default="${2:-y}"
    read -rp "  $prompt [y/n] ($default): " ans
    ans="${ans:-$default}"
    [[ "$ans" =~ ^[Yy] ]]
}

# ─── Template sync — rsync-style update of unchanged package files ───────────
# Copies each tracked file from $VUTURELAND_DIR to $VUTURELAND_USER_DIR unless
# the destination has been edited (mtime newer than source by more than a few
# seconds OR contents differ from a previously-tracked-shipped version).
# Files in $WALLUST_OUTPUTS are never overwritten — those are wallust's job.
sync_templates() {
    local _dir
    mkdir -p "$VUTURELAND_USER_DIR"

    # Drop stale symlinks left over from older versions of this script
    for _dir in rofi kitty swaync assets hypr.lua waybar-modular; do
        [[ -L "$VUTURELAND_USER_DIR/$_dir" ]] && rm -f "$VUTURELAND_USER_DIR/$_dir"
    done

    # Files that wallust writes — never overwrite these
    local _wallust_outputs=(
        "assets/colors_gtk.css"
        "assets/colors_hyprland.conf"
        "hypr.lua/colors.lua"
        "kitty/colors.conf"
        "rofi/assets/colors.rasi"
    )
    is_wallust_output() {
        local rel="$1"
        for w in "${_wallust_outputs[@]}"; do [[ "$rel" == "$w" ]] && return 0; done
        return 1
    }

    # Sync these subtrees
    for _dir in kitty rofi swaync hypr.lua waybar-modular; do
        local src="$VUTURELAND_DIR/$_dir"
        local dst="$VUTURELAND_USER_DIR/$_dir"
        [[ -d "$src" ]] || continue
        mkdir -p "$dst"

        # Walk the source tree, copy missing or older files (skip wallust outputs)
        while IFS= read -r -d '' file; do
            local rel="${file#$VUTURELAND_DIR/}"
            local user_path="$VUTURELAND_USER_DIR/$rel"
            is_wallust_output "$rel" && continue

            # Replace any pre-existing symlink (from older versions or dev
            # setup) with a real file so cp doesn't follow it into a read-only
            # source dir.
            if [[ -L "$user_path" ]]; then
                rm -f "$user_path"
            fi

            if [[ ! -e "$user_path" ]]; then
                mkdir -p "$(dirname "$user_path")"
                cp "$file" "$user_path"
            elif [[ "$file" -nt "$user_path" ]]; then
                # Package file newer than user copy — refresh it. (mtime
                # comparison protects user-edited files: if the user modified
                # the file after the package was built/installed, the user's
                # copy is newer and we leave it.)
                mkdir -p "$(dirname "$user_path")"
                cp "$file" "$user_path"
            fi
        done < <(find "$src" -type f -print0)
    done

    # Make sure assets/, gui/ exist in user dir (wallust + gui write into these)
    mkdir -p "$VUTURELAND_USER_DIR/assets" "$VUTURELAND_USER_DIR/gui"

    # Read-only assets (wallpaper, icons, scripts) live in the package and are
    # referenced by ~/.config/vutureland/assets/... from hypridle.conf,
    # hyprlock-themes, bt-notify.sh etc. Expose them via symlinks so those
    # absolute paths resolve. wallust outputs land alongside as real files.
    for _sub in wallpaper icons scripts; do
        local _link="$VUTURELAND_USER_DIR/assets/$_sub"
        local _real="$VUTURELAND_DIR/assets/$_sub"
        [[ -d "$_real" ]] || continue
        # If something there isn't already pointing at the right target, replace
        if [[ -L "$_link" ]]; then
            [[ "$(readlink "$_link")" == "$_real" ]] || { rm -f "$_link"; ln -sf "$_real" "$_link"; }
        elif [[ ! -e "$_link" ]]; then
            ln -sf "$_real" "$_link"
        fi
    done

    # Seed initial wallust outputs from package defaults if missing.
    # A symlink here would be from an older dev setup pointing at a read-only
    # location — replace it with a real file so wallust can write to it.
    for _f in "${_wallust_outputs[@]}"; do
        local _dst="$VUTURELAND_USER_DIR/$_f"
        [[ -L "$_dst" ]] && rm -f "$_dst"
        if [[ ! -f "$_dst" && -f "$VUTURELAND_DIR/$_f" ]]; then
            mkdir -p "$(dirname "$_dst")"
            cp "$VUTURELAND_DIR/$_f" "$_dst"
        fi
    done

    # hypridle and hyprlock ignore the --config flag on some versions — they
    # only read $XDG_CONFIG_HOME/hypr/{hypridle,hyprlock}.conf. Symlink ours
    # into the standard path so the daemons can always find the config.
    mkdir -p "$HOME/.config/hypr"
    for _f in hypridle.conf hyprlock.conf; do
        local _link="$HOME/.config/hypr/$_f"
        local _target="$VUTURELAND_USER_DIR/hypr.lua/$_f"
        [[ -f "$_target" ]] || continue
        # Re-point unless it's already our symlink. This also replaces a plain
        # regular file left behind by an older install or a manual `cp` — otherwise
        # hyprlock keeps reading that stale copy and never sees what the GUI writes.
        if [[ -L "$_link" && "$(readlink "$_link")" == "$_target" ]]; then
            continue
        fi
        rm -f "$_link"
        ln -sf "$_target" "$_link"
    done

    # swaync gets started by its systemd user unit OR via D-Bus activation,
    # always without our -c / -s arguments, so it reads ~/.config/swaync/style.css.
    # We can't just symlink our style.css there: GTK4 resolves its
    # `@import url("../assets/colors_gtk.css")` against the *symlink's* directory
    # (~/.config/swaync/), not the real file, so the wallust palette import would
    # silently fail and swaync would fall back to an unthemed look. Instead write
    # a real style.css with the import rewritten to the absolute palette path.
    # (config.json is written here by launch-swaync.sh with dynamic margins.)
    mkdir -p "$HOME/.config/swaync"
    local _swstyle="$HOME/.config/swaync/style.css"
    local _swstyle_src="$VUTURELAND_USER_DIR/swaync/style.css"
    local _sw_colors="$VUTURELAND_USER_DIR/assets/colors_gtk.css"
    [[ -L "$_swstyle" ]] && rm -f "$_swstyle"
    if [[ -f "$_swstyle_src" ]]; then
        sed "s#\.\./assets/colors_gtk\.css#${_sw_colors}#" "$_swstyle_src" > "$_swstyle"
    fi

    # ── GTK theme + palette wiring ────────────────────────────────────
    # For wallust colours to actually take effect in GTK apps, two things
    # must be true:
    #   1) The active GTK theme must use Adwaita's named colours (e.g.
    #      @window_bg_color, @accent_bg_color). Themes with hardcoded hex
    #      values (Breeze, Arc, ...) ignore @define-color overrides.
    #      adw-gtk3 / adw-gtk3-dark are pure-Adwaita ports that respect them.
    #   2) ~/.config/gtk-{3,4}.0/gtk.css must @import wallust.css LAST so
    #      its overrides win over any theme-shipped @define-color blocks.
    #
    # We seed settings.ini with adw-gtk3-dark + dark color-scheme if the
    # user hasn't picked something else; we never overwrite an existing
    # gtk-theme-name= line.
    for _gtk in gtk-3.0 gtk-4.0; do
        local _gdir="$HOME/.config/$_gtk"
        local _ini="$_gdir/settings.ini"
        mkdir -p "$_gdir" 2>/dev/null || true
        [[ -w "$_gdir" ]] || continue
        if [[ ! -f "$_ini" ]]; then
            cat > "$_ini" <<EOF
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-application-prefer-dark-theme=true
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-font-name=FantasqueSansM Nerd Font  10
EOF
        else
            # Make sure the dark-mode hint is on (Adwaita-Dark sees it)
            if ! grep -q 'gtk-application-prefer-dark-theme' "$_ini"; then
                printf '\ngtk-application-prefer-dark-theme=true\n' >> "$_ini"
            fi
        fi
    done

    # Tell GTK4 / libadwaita to prefer dark; safe to set every run.
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
    fi

    # GTK 3 / 4 apps load colours from ~/.config/gtk-{3,4}.0/gtk.css. Wallust
    # writes wallust.css into those folders, but only an @import in gtk.css
    # actually pulls the palette in. Create the gtk.css if missing; append
    # the import line if it already exists but doesn't reference wallust.css.
    local _me="$(id -un):$(id -gn)"
    for _gtk in gtk-3.0 gtk-4.0; do
        local _gdir="$HOME/.config/$_gtk"
        local _gcss="$_gdir/gtk.css"
        mkdir -p "$_gdir" 2>/dev/null || true
        if [[ ! -w "$_gdir" ]]; then
            echo "  ! ~/.config/$_gtk is not writable — skipping gtk.css wallust import"
            echo "    fix: sudo chown -R $_me ~/.config/$_gtk"
            continue
        fi
        if [[ ! -f "$_gcss" ]]; then
            echo '@import url("wallust.css");' > "$_gcss"
        elif [[ ! -w "$_gcss" ]]; then
            echo "  ! ~/.config/$_gtk/gtk.css is not writable — skipping wallust import"
            echo "    fix: sudo chown $_me ~/.config/$_gtk/gtk.css"
        elif ! grep -q 'wallust.css' "$_gcss"; then
            printf '\n@import url("wallust.css");\n' >> "$_gcss"
        fi
    done
}

# Generate a minimal but useful waybar config inline — no external template
# files needed. The user can switch styles / add modules later through the
# settings GUI (Super + X → Bar). Defined here so --sync can call it too.
apply_default_bar() {
    local monitor="$1"
    local dest="$VUTURELAND_USER_DIR/waybar-modular/output/miboro/bar/top/$monitor"
    # Regenerate if the existing config still points at the package dir
    # (would import colours from a read-only path that wallust never updates).
    if [[ -f "$dest/style.css" ]] && grep -q "$VUTURELAND_USER_DIR" "$dest/style.css"; then
        ok "Bar config for $monitor already exists — skipping."
        return
    fi
    rm -rf "$dest"
    mkdir -p "$dest"

    local mods="$VUTURELAND_USER_DIR/waybar-modular/config/miboro/modules/horizontal"
    local base="$VUTURELAND_USER_DIR/waybar-modular/config/miboro/base/base-top"

    # Only show the battery module on devices that actually have a battery.
    local has_battery=false
    compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1 && has_battery=true

    # Module config.json files to pull in. The drawers (performance/audio/tray)
    # only *reference* their child modules, so those children must be included
    # too or waybar can't resolve them.
    local module_dirs=(
        clock separator
        a-left-drawer-performance performance temperature-gpu temperature-cpu memory cpu
        actionuser
        workspaces submap
        cava
        a-right-drawer-audio pulseaudio mpris bluetooth
        a-right-drawer-tray notification tray
    )
    $has_battery && module_dirs+=(battery)

    # Comma-joined "include" entries for every module config.json.
    local _inc=()
    local m
    for m in "${module_dirs[@]}"; do _inc+=("\"$mods/$m/config.json\""); done
    local includes; includes=$(IFS=,; echo "${_inc[*]}")

    # Right group: battery only appended when the device has one.
    local right='"custom/cava", "group/audio_drawer", "custom/separator", "group/tray_drawer"'
    $has_battery && right+=', "battery"'

    cat > "$dest/groups.json" <<EOF
{
    "include": [ $includes ],
    "group/left":   { "orientation": "horizontal",
                      "modules": ["clock", "custom/separator", "group/performance_drawer", "custom/separator", "custom/actionuser"] },
    "group/center": { "orientation": "horizontal",
                      "modules": ["hyprland/workspaces", "hyprland/submap"] },
    "group/right":  { "orientation": "horizontal",
                      "modules": [$right] }
}
EOF

    if [[ -f "$base/bar.config.json" ]]; then
        jq --arg mon "$monitor" \
           --arg id "bar-top-$monitor" \
           --arg groups "$dest/groups.json" \
           '. + {
                output: $mon,
                id: $id,
                include: [$groups],
                "modules-left":   ["group/left"],
                "modules-center": ["group/center"],
                "modules-right":  ["group/right"]
            }' "$base/bar.config.json" > "$dest/config.json"
    else
        warn "$base/bar.config.json missing — using minimal config"
        cat > "$dest/config.json" <<EOF
{
    "name": "topbar-$monitor",
    "output": "$monitor",
    "layer": "top",
    "position": "top",
    "include": ["$dest/groups.json"],
    "modules-left":   ["group/left"],
    "modules-center": ["group/center"],
    "modules-right":  ["group/right"]
}
EOF
    fi

    {
        echo "@import url(\"$base/bar.css\");"
        for m in "${module_dirs[@]}"; do
            local css="$mods/$m/style.css"
            [[ -f "$css" ]] && echo "@import url(\"$css\");"
        done
    } > "$dest/style.css"

    ok "Created default bar for $monitor"
}

# ─── --sync: refresh package templates and exit ──────────────────────────────
if [[ "$SYNC_MODE" == true ]]; then
    echo ""
    echo "  ${BOLD}${CYAN}── Syncing Vutureland templates${RST}"
    echo ""
    echo "  Source: $VUTURELAND_DIR"
    echo "  Dest:   $VUTURELAND_USER_DIR"
    echo ""
    sync_templates
    ok "Templates synced."

    # Regenerate any bar configs that still point at the package dir
    if command -v hyprctl >/dev/null 2>&1 && hyprctl monitors -j >/dev/null 2>&1; then
        while IFS= read -r _mon; do
            [[ -n "$_mon" ]] && apply_default_bar "$_mon"
        done < <(hyprctl monitors -j | jq -r '.[].name')
    fi

    # Reload anything that might be running, so the user doesn't need to
    # log out / log in to pick up the new files.
    if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
        hyprctl reload >/dev/null 2>&1 && ok "Hyprland reloaded"
    fi
    if pgrep -x waybar >/dev/null 2>&1; then
        "$VUTURELAND_DIR/assets/scripts/launch-waybar.sh" >/dev/null 2>&1 \
            && ok "Waybar restarted"
    fi
    if pgrep -x swaync >/dev/null 2>&1; then
        "$VUTURELAND_DIR/assets/scripts/launch-swaync.sh" >/dev/null 2>&1 \
            && ok "swaync restarted"
    fi
    # Settings-panel daemon: easiest to bounce.
    if pgrep -f "python3.*gui/main.py" >/dev/null 2>&1; then
        "$VUTURELAND_DIR/bin/vutureland" --end  >/dev/null 2>&1 || true
        "$VUTURELAND_DIR/bin/vutureland" --daemon >/dev/null 2>&1 &
        ok "Settings panel restarted"
    fi
    # Pre-generate wallpaper thumbnails for the picker.
    if [[ -x "$VUTURELAND_DIR/rofi/assets/generate-thumbnail.sh" ]]; then
        ( "$VUTURELAND_DIR/rofi/assets/generate-thumbnail.sh" >/dev/null 2>&1 ) &
        ok "Generating wallpaper thumbnails in the background"
    fi
    echo ""
    exit 0
fi

# ─── Header ──────────────────────────────────────────────────────────────────
clear; echo ""
echo "  ${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RST}"
echo "  ${BOLD}${CYAN}║            Welcome to Vutureland                         ║${RST}"
echo "  ${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RST}"
echo ""
echo "  This wizard sets up vutureland on a fresh system."
echo "  It will start services, configure Hyprland, apply"
echo "  a default Waybar layout, and set the initial wallpaper."
echo ""
hr; echo ""

# ─── 0) Package installation ──────────────────────────────────────────────────
say "Package installation"

REQUIRED_PKGS=(
    hypridle hyprlock hyprpolkitagent
    waybar rofi-wayland kitty
    swaync cava
    awww wallust
    playerctl jq socat fastfetch tmux
    network-manager-applet gnome-keyring
    nextcloud-client localsend
    openrgb ddcutil grim hyprshot python
)

if ask_yn "Check and install missing packages?" "y"; then
    missing_pacman=()
    missing_aur=()

    for pkg in "${REQUIRED_PKGS[@]}"; do
        if pacman -Q "$pkg" &>/dev/null; then
            continue
        fi
        if pacman -Si "$pkg" &>/dev/null 2>&1; then
            missing_pacman+=("$pkg")
        else
            missing_aur+=("$pkg")
        fi
    done

    if [[ ${#missing_pacman[@]} -eq 0 && ${#missing_aur[@]} -eq 0 ]]; then
        ok "All packages already installed."
    else
        if [[ ${#missing_pacman[@]} -gt 0 ]]; then
            echo "  Installing from pacman: ${missing_pacman[*]}"
            sudo pacman -S --noconfirm "${missing_pacman[@]}" \
                && ok "pacman packages installed." \
                || warn "Some pacman packages failed — check output above."
        fi

        if [[ ${#missing_aur[@]} -gt 0 ]]; then
            if ! command -v yay &>/dev/null; then
                warn "yay not found. Cannot install AUR packages: ${missing_aur[*]}"
                warn "Install yay first, then re-run this wizard."
            else
                echo "  Installing from AUR (yay): ${missing_aur[*]}"
                yay -S --noconfirm "${missing_aur[@]}" \
                    && ok "AUR packages installed." \
                    || warn "Some AUR packages failed — check output above."
            fi
        fi
    fi
else
    ok "Skipping package installation."
fi

# ─── 1) User avatar check ─────────────────────────────────────────────────────
say "User Avatar (~/.face)"

if [[ -f "$HOME/.face" ]]; then
    ok "Found ~/.face — will be shown in the Waybar user button."
else
    warn "No user avatar found at ~/.face"
    echo ""
    echo "  The default Waybar layout includes an interactive user button"
    echo "  that displays your profile picture from ~/.face."
    echo "  Any image file works (PNG, JPG). This is optional — Waybar"
    echo "  will work fine without it, but the button area will be empty."
    echo ""
    echo "  To add one later:  cp your-photo.png ~/.face"
    echo ""
    read -rp "  Press Enter to continue without an avatar, or Ctrl+C to abort. "
fi

# ─── 1.5) Seed user dir + environment ────────────────────────────────────────
# Must run BEFORE we start services — hypridle and friends look for config
# files in $VUTURELAND_USER_DIR.
say "Setting up ~/.config/vutureland/"

# wallust symlink — wallust expects its config at ~/.config/wallust/
if [[ ! -e "$HOME/.config/wallust" ]]; then
    ln -sf "$VUTURELAND_DIR/wallust" "$HOME/.config/wallust"
    ok "Linked ~/.config/wallust → vutureland/wallust"
fi
# hypridle / hyprlock symlinks under ~/.config/hypr/ are created by sync_templates

# Copy templates from the package into the user dir
sync_templates
ok "Seeded ~/.config/vutureland/ from package templates"

# Write VUTURELAND_DIR / VUTURELAND_USER_DIR into systemd user environment
# (takes effect on next login; we already have them exported in this shell)
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/vutureland.conf" <<EOF
VUTURELAND_DIR=$VUTURELAND_DIR
VUTURELAND_USER_DIR=$VUTURELAND_USER_DIR
EOF
ok "Wrote ~/.config/environment.d/vutureland.conf"

# Also push them into the running systemd user session so child processes
# (services we start below) inherit them right away.
systemctl --user import-environment VUTURELAND_DIR VUTURELAND_USER_DIR 2>/dev/null || true

# ─── 2) Background services ───────────────────────────────────────────────────
say "Starting background services"

AUTOSTART_LUA="$VUTURELAND_DIR/hypr.lua/modules/autostart.lua"

# Kill an existing instance and start the daemon in the background.
# Success is determined by looking for the actual binary in the process list
# (not the wrapper subshell), because:
#   - gnome-keyring-daemon forks and the parent exits immediately
#   - launch-*.sh wrappers exec the real daemon then exit themselves
_start_daemon() {
    local cmd_raw="$1"
    local cmd="${cmd_raw//\~/$HOME}"
    local first_word binary target

    first_word=$(printf '%s' "$cmd" | awk '{print $1}')
    binary=$(basename "$first_word")

    if [[ "$first_word" == "systemctl" ]]; then
        if eval "$cmd" 2>/dev/null; then
            ok "$binary"
        else
            warn "Failed: $binary"
            notify-send -a "Vutureland" "⚠ Autostart failed" "$binary" 2>/dev/null || true
        fi
        return
    fi

    # Pick the target process name to look for in pgrep
    case "$binary" in
        launch-waybar.sh) target="waybar" ;;
        launch-swaync.sh) target="swaync" ;;
        launch-*.sh)      target="${binary#launch-}"; target="${target%.sh}" ;;
        *)                target="$binary" ;;
    esac

    pkill -f "$target" 2>/dev/null || true
    sleep 0.1

    eval "$cmd" &>/dev/null &
    disown 2>/dev/null
    sleep 0.5

    if pgrep -f "$target" >/dev/null; then
        ok "$binary"
    else
        warn "Failed: $binary"
        notify-send -a "Vutureland" "⚠ Autostart failed" "$binary" 2>/dev/null || true
    fi
}

# Fire-and-forget (exec_once_daemons): run without killing existing instances.
_run_once() {
    local cmd_raw="$1"
    local cmd="${cmd_raw//\~/$HOME}"
    local binary
    binary=$(basename "$(printf '%s' "$cmd" | awk '{print $1}')")
    eval "$cmd" &>/dev/null &
    disown "$!" 2>/dev/null
    ok "$binary"
}

# ── System daemons ─────────────────────────────────────
# Mirrored from hypr.lua/modules/autostart.lua so we don't have to parse Lua
# string-concatenation syntax. Keep these in sync when daemons are added.
_SYSTEM_DAEMONS=(
    # hypridle picks up ~/.config/hypr/hypridle.conf via the symlink seeded above
    "hypridle"
    "awww-daemon"
    "nm-applet"
    "systemctl --user start hyprpolkitagent"
    "gnome-keyring-daemon --start --components=secrets"
    "$VUTURELAND_DIR/assets/scripts/launch-swaync.sh"
    "wl-paste --watch clipvault store"
    "$VUTURELAND_DIR/assets/scripts/float-cascade.sh"
)
for cmd in "${_SYSTEM_DAEMONS[@]}"; do
    _start_daemon "$cmd"
done

# ── exec_once_daemons from user_settings.lua ───────────
if [[ -f "$USER_SETTINGS" ]]; then
    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        _run_once "$cmd"
    done < <(awk '
        /<<<AUTOSTART-START>>>/ { in_s=1; next }
        /<<<AUTOSTART-END>>>/ { in_s=0 }
        in_s && /exec_once_daemons/ { in_list=1; next }
        in_s && in_list && /^\s*\}/ { in_list=0 }
        in_s && in_list {
            s = $0
            sub(/^[^"]*"/, "", s)
            sub(/".*$/, "", s)
            if (s != "") print s
        }
    ' "$USER_SETTINGS")
fi

# ─── 3) Hyprland config ───────────────────────────────────────────────────────
say "Hyprland configuration"

HYPR_CONFIG="$HOME/.config/hypr"

if [[ -d "$HYPR_CONFIG" && ! -d "$HOME/.config/hypr.bak" ]]; then
    mv "$HYPR_CONFIG" "$HOME/.config/hypr.bak"
    ok "Backed up ~/.config/hypr → ~/.config/hypr.bak"
elif [[ -d "$HOME/.config/hypr.bak" ]]; then
    warn "~/.config/hypr.bak already exists — skipping backup."
fi

mkdir -p "$HYPR_CONFIG"

# Always (re)generate the entry point so it points at the currently-installed
# vutureland package (paths embedded inline). Back up any user-edited version.
_HYP_ENTRY="$HYPR_CONFIG/hyprland.lua"
_NEW_ENTRY=$(cat <<EOF
local base = "$VUTURELAND_DIR/hypr.lua/"
VTL_DIR      = base:match("^(.*)/hypr%.lua/?$")
VTL_USER_DIR = "$VUTURELAND_USER_DIR"
package.path = base .. "?.lua;"
            .. base .. "modules/?.lua;"
            .. base .. "modules/?/init.lua;"
            .. package.path
dofile(base .. "hyprland.lua")
EOF
)

if [[ -f "$_HYP_ENTRY" ]] && ! diff -q <(echo "$_NEW_ENTRY") "$_HYP_ENTRY" >/dev/null 2>&1; then
    cp "$_HYP_ENTRY" "$_HYP_ENTRY.bak"
    ok "Backed up existing hyprland.lua → hyprland.lua.bak"
fi
echo "$_NEW_ENTRY" > "$_HYP_ENTRY"
ok "Wrote ~/.config/hypr/hyprland.lua (→ $VUTURELAND_DIR)"

# ─── 4) Monitor + Workspace setup ────────────────────────────────────────────
say "Monitor & Workspace setup"
echo "  Running hyprland.sh in minimal mode (monitors + workspaces only)."
echo "  Run  ~/.config/vutureland/.setup/hyprland.sh  later for full config."
echo ""

bash "$VUTURELAND_DIR/.setup/hyprland.sh" --minimal

# ─── 5) Read selected monitors ────────────────────────────────────────────────
mon1=""
mon2=""
if [[ -f "$USER_SETTINGS" ]]; then
    mon1=$(grep -oP '^mon1\s*=\s*"\K[^"]+' "$USER_SETTINGS" 2>/dev/null | head -1 || true)
    mon2=$(grep -oP '^mon2\s*=\s*"\K[^"]+' "$USER_SETTINGS" 2>/dev/null | head -1 || true)
fi

if [[ -z "$mon1" ]]; then
    warn "Could not read monitor from user_settings.conf — defaulting to 'DP-2'."
    mon1="DP-2"
fi

ok "Primary monitor: $mon1"
[[ -n "$mon2" ]] && ok "Secondary monitor: $mon2"

# ─── 6) Fix user-specific path in actionuser CSS ─────────────────────────────
FACE_CSS="$VUTURELAND_DIR/waybar-modular/modules/actionuser/style.css"
if [[ -f "$FACE_CSS" ]]; then
    sed -i "s|background-image: url(\"[^\"]*\.face\")|background-image: url(\"$HOME/.face\")|g" \
        "$FACE_CSS"
    ok "Updated face image path in actionuser CSS"
fi

# ─── 7) Generate default Waybar config ───────────────────────────────────────
say "Generating default Waybar layout"

apply_default_bar "$mon1"
[[ -n "$mon2" ]] && apply_default_bar "$mon2"

# ─── 8) Launch Waybar ────────────────────────────────────────────────────────
say "Starting Waybar"
"$VUTURELAND_DIR/assets/scripts/launch-waybar.sh" >/dev/null 2>&1 && ok "Waybar running." \
    || warn "Waybar did not start cleanly — open the settings GUI (Super+X) to inspect."

# ─── 9) Default wallpaper ─────────────────────────────────────────────────────
say "Setting default wallpaper"

DEFAULT_WP="$VUTURELAND_DIR/assets/wallpaper/horizontal/wp_qUmiue_hor.jpg"
if [[ -f "$DEFAULT_WP" ]]; then
    bash "$VUTURELAND_DIR/assets/scripts/wallpaper-set.sh" --no-showcase "$DEFAULT_WP"
    ok "Wallpaper set."
else
    warn "Default wallpaper not found: $DEFAULT_WP"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
hr
echo ""
echo "  ${BOLD}${GREEN}Vutureland is ready!${RST}"
echo ""
echo "  To reconfigure later:"
echo "    ${DIM}~/.config/vutureland/.setup/hyprland.sh${RST}  – Hyprland (monitors, workspaces, …)"
echo "    ${DIM}~/.config/vutureland/.setup/waybar.sh${RST}    – Waybar modules"
echo ""
