#!/usr/bin/env bash
# Velumeron bootstrap (non-interactive apart from the package install).
# Seeds the user dir, wires the environment and auto-configures monitors;
# the interactive part of first-run setup is the onboarding GUI, which the
# shell opens by itself afterwards (see quickshell/onboarding/).
#
#   welcome_to_velumeron.sh           First-run bootstrap
#   welcome_to_velumeron.sh --sync    Refresh package templates from
#                                      $VELUMERON_DIR without touching user
#                                      state (use after a pacman/yay upgrade)
#   --sync --no-restart               Same, but never restarts the shell
#                                      (used by the update-report GUI)

set -euo pipefail

# Detect the package dir from this script's own location (realpath resolves
# the /usr/bin/velumeron-setup symlink → /usr/share/velumeron/…). We trust
# a pre-set VELUMERON_DIR env var only if it points at a real velumeron
# package — otherwise it would be a stale value from an older install and
# corrupt every path we write (e.g. into ~/.config/hypr/hyprland.lua).
_SELF_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
if [[ -z "${VELUMERON_DIR:-}" \
   || ! -f "$VELUMERON_DIR/bin/velumeron" \
   || ! -d "$VELUMERON_DIR/hypr.lua/modules" ]]; then
    VELUMERON_DIR="$_SELF_DIR"
fi
: "${VELUMERON_USER_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/velumeron}"
export VELUMERON_DIR VELUMERON_USER_DIR

# Never run this script as root. It writes into the user's home and would
# end up owning ~/.config/velumeron/ as root, breaking every subsequent
# non-root run with permission-denied. Package installation (pacman/yay)
# uses sudo internally, but THIS wizard must run as the desktop user.
if [[ $EUID -eq 0 ]]; then
    echo ""
    echo "  velumeron-setup must NOT be run as root."
    echo "  Drop sudo and re-run as your desktop user:"
    echo ""
    echo "      velumeron-setup ${1:-}"
    echo ""
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo "  If files in your home are already owned by root, fix them:"
        echo "      sudo chown -R $SUDO_USER:$SUDO_USER \\"
        echo "          ~$SUDO_USER/.config/velumeron \\"
        echo "          ~$SUDO_USER/.config/hypr \\"
        echo "          ~$SUDO_USER/.config/wallust \\"
        echo "          ~$SUDO_USER/.config/environment.d"
        echo ""
    fi
    exit 1
fi
USER_SETTINGS="$VELUMERON_USER_DIR/hypr.lua/user_settings.lua"

# Parse flags
SYNC_MODE=false
NO_RESTART=false
AUTO_MODE=false
for arg in "$@"; do
    case "$arg" in
        --sync) SYNC_MODE=true ;;
        # For --sync runs triggered FROM the running shell (update report GUI):
        # restarting quickshell here would kill the caller and re-trigger the
        # sync on the next start — an endless loop.
        --no-restart) NO_RESTART=true ;;
        # Fully unattended bootstrap, run by velumeron-session before Hyprland
        # starts: no prompts (packages come from the AUR dependency list), no
        # daemon/shell launching (autostart.lua does that in-session).
        --auto) AUTO_MODE=true ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--sync [--no-restart]] [--auto]"
            echo "  --sync         Refresh package templates without re-running setup"
            echo "  --no-restart   With --sync: don't restart the running shell"
            echo "  --auto         Unattended bootstrap (used by velumeron-session)"
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
# Copies each tracked file from $VELUMERON_DIR to $VELUMERON_USER_DIR unless
# the destination has been edited (mtime newer than source by more than a few
# seconds OR contents differ from a previously-tracked-shipped version).
# Files in $WALLUST_OUTPUTS are never overwritten — those are wallust's job.
sync_templates() {
    local _dir
    mkdir -p "$VELUMERON_USER_DIR"

    # Drop stale symlinks left over from older versions of this script
    for _dir in rofi kitty assets hypr.lua waybar-modular; do
        [[ -L "$VELUMERON_USER_DIR/$_dir" ]] && rm -f "$VELUMERON_USER_DIR/$_dir"
    done
    # waybar is retired — remove any previously-seeded copy so it can't linger.
    [[ -e "$VELUMERON_USER_DIR/waybar-modular" ]] && rm -rf "$VELUMERON_USER_DIR/waybar-modular"

    # Files that wallust writes — never overwrite these
    local _wallust_outputs=(
        "assets/colors_gtk.css"
        "assets/colors_hyprland.conf"
        "hypr.lua/colors.lua"
        "kitty/colors.conf"
        "rofi/assets/colors.rasi"
        # Device-specific config (monitors/workspaces/…): a repo/package copy
        # of this untracked file must never clobber the user's machine setup
        # via the mtime rule below.
        "hypr.lua/user_settings.lua"
    )
    is_wallust_output() {
        local rel="$1"
        for w in "${_wallust_outputs[@]}"; do [[ "$rel" == "$w" ]] && return 0; done
        return 1
    }

    # Sync these subtrees
    for _dir in kitty rofi hypr.lua; do
        local src="$VELUMERON_DIR/$_dir"
        local dst="$VELUMERON_USER_DIR/$_dir"
        [[ -d "$src" ]] || continue
        mkdir -p "$dst"

        # Walk the source tree, copy missing or older files (skip wallust outputs)
        while IFS= read -r -d '' file; do
            local rel="${file#$VELUMERON_DIR/}"
            local user_path="$VELUMERON_USER_DIR/$rel"
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
    mkdir -p "$VELUMERON_USER_DIR/assets" "$VELUMERON_USER_DIR/gui"

    # Read-only assets (wallpaper, icons, scripts) live in the package and are
    # referenced by ~/.config/velumeron/assets/... from hypridle.conf,
    # hyprlock-themes, bt-notify.sh etc. Expose them via symlinks so those
    # absolute paths resolve. wallust outputs land alongside as real files.
    for _sub in wallpaper icons scripts; do
        local _link="$VELUMERON_USER_DIR/assets/$_sub"
        local _real="$VELUMERON_DIR/assets/$_sub"
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
        local _dst="$VELUMERON_USER_DIR/$_f"
        [[ -L "$_dst" ]] && rm -f "$_dst"
        if [[ ! -f "$_dst" && -f "$VELUMERON_DIR/$_f" ]]; then
            mkdir -p "$(dirname "$_dst")"
            cp "$VELUMERON_DIR/$_f" "$_dst"
        fi
    done

    # hypridle and hyprlock ignore the --config flag on some versions — they
    # only read $XDG_CONFIG_HOME/hypr/{hypridle,hyprlock}.conf. Symlink ours
    # into the standard path so the daemons can always find the config.
    mkdir -p "$HOME/.config/hypr"
    for _f in hypridle.conf hyprlock.conf; do
        local _link="$HOME/.config/hypr/$_f"
        local _target="$VELUMERON_USER_DIR/hypr.lua/$_f"
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

    # Migrate pre-v0.1.0 hypridle configs: launching hyprlock from before_sleep_cmd
    # blocked the inhibitor and let the machine suspend mid-lock-init — hyprlock
    # (and the session) died on wake. The mtime rule above never fixes this for
    # users who saved timeouts via the GUI (their copy is newer than the package),
    # so patch the general block in place; the listener timeouts stay untouched.
    local _hc="$VELUMERON_USER_DIR/hypr.lua/hypridle.conf"
    if [[ -f "$_hc" ]] && grep -q 'before_sleep_cmd.*launch-hyprlock' "$_hc"; then
        python3 - "$_hc" <<'PY'
import re, sys
p = sys.argv[1]
c = open(p).read()
c = re.sub(r'(?m)^(\s*before_sleep_cmd\s*=\s*).*launch-hyprlock\.sh.*$',
           r'\1loginctl lock-session', c)
c = re.sub(r'(?m)^(\s*after_sleep_cmd\s*=\s*)$',
           "\\1hyprctl dispatch 'hl.dsp.dpms(\"on\")'", c)
if 'inhibit_sleep' not in c:
    c = re.sub(r'(?m)^(\s*after_sleep_cmd.*)$',
               r'\1\n    inhibit_sleep           = 3', c, count=1)
open(p, 'w').write(c)
PY
        ok "Migrated hypridle.conf suspend sequencing (lock-before-sleep)"
        if pgrep -x hypridle >/dev/null 2>&1; then
            pkill -x hypridle 2>/dev/null || true
            sleep 0.3
            setsid -f hypridle >/dev/null 2>&1 || true
        fi
    fi
    # Migrate after_sleep to the retrying wake script: a single dpms-on can fire
    # before the displays finished re-initializing — session alive, screens dark.
    if [[ -f "$_hc" ]] && grep -qF "after_sleep_cmd         = hyprctl dispatch 'hl.dsp.dpms(\"on\")'" "$_hc"; then
        sed -i "s|after_sleep_cmd         = hyprctl dispatch 'hl.dsp.dpms(\"on\")'|after_sleep_cmd         = ~/.config/velumeron/assets/scripts/resume-wake.sh|" "$_hc"
        ok "Migrated hypridle.conf resume wake to the retrying script"
        if pgrep -x hypridle >/dev/null 2>&1; then
            pkill -x hypridle 2>/dev/null || true
            sleep 0.3
            setsid -f hypridle >/dev/null 2>&1 || true
        fi
    fi
    # Migrate the idle-suspend listener to the guarded script: a bare
    # `systemctl suspend` on-timeout fires right through video encodes,
    # builds and playing audio (idle ≠ no work).
    if [[ -f "$_hc" ]] && grep -Eq '^\s*on-timeout\s*=\s*systemctl suspend\s*$' "$_hc"; then
        sed -i -E 's|^(\s*on-timeout\s*=\s*)systemctl suspend\s*$|\1~/.config/velumeron/assets/scripts/idle-suspend.sh|' "$_hc"
        ok "Migrated hypridle.conf idle-suspend to the guarded script"
        if pgrep -x hypridle >/dev/null 2>&1; then
            pkill -x hypridle 2>/dev/null || true
            sleep 0.3
            setsid -f hypridle >/dev/null 2>&1 || true
        fi
    fi

    # ── Bundled fonts ─────────────────────────────────────────────────
    # The configs rely on specific fonts (FantasqueSansM Nerd Font, Atomic Age,
    # Audiowide for waybar/swaync/rofi/hyprlock). Install the bundled copies into
    # the per-user font dir so a fresh client renders correctly with no manual
    # step and no root. Idempotent: only copy new/updated files, rebuild the cache
    # only when something changed.
    local _font_src="$VELUMERON_DIR/assets/fonts"
    local _font_dst="$HOME/.local/share/fonts/velumeron"
    if [[ -d "$_font_src" ]]; then
        mkdir -p "$_font_dst"
        local _font_changed=false _ff _fd
        for _ff in "$_font_src"/*.ttf "$_font_src"/*.otf; do
            [[ -e "$_ff" ]] || continue
            _fd="$_font_dst/$(basename "$_ff")"
            if [[ ! -f "$_fd" || "$_ff" -nt "$_fd" ]]; then
                cp "$_ff" "$_fd" && _font_changed=true
            fi
        done
        if [[ "$_font_changed" == true ]]; then
            command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$_font_dst" >/dev/null 2>&1 || true
            ok "Fonts installed to $_font_dst"
        fi
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

# ─── --sync: refresh package templates and exit ──────────────────────────────
if [[ "$SYNC_MODE" == true ]]; then
    echo ""
    echo "  ${BOLD}${CYAN}── Syncing Velumeron templates${RST}"
    echo ""
    echo "  Source: $VELUMERON_DIR"
    echo "  Dest:   $VELUMERON_USER_DIR"
    echo ""
    sync_templates
    ok "Templates synced."

    # Reload anything that might be running, so the user doesn't need to
    # log out / log in to pick up the new files.
    if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
        hyprctl reload >/dev/null 2>&1 && ok "Hyprland reloaded"
    fi
    # Restart the shell (bar + OSD + notifications + settings) if it's running, so
    # the refreshed palette/config takes effect without a re-login.
    if [[ "$NO_RESTART" != true ]] && pgrep -x quickshell >/dev/null 2>&1; then
        bash "$VELUMERON_DIR/assets/scripts/launch-shell.sh" >/dev/null 2>&1 \
            && ok "Shell restarted"
    fi
    # Pre-generate wallpaper thumbnails for the picker.
    if [[ -x "$VELUMERON_DIR/rofi/assets/generate-thumbnail.sh" ]]; then
        ( "$VELUMERON_DIR/rofi/assets/generate-thumbnail.sh" >/dev/null 2>&1 ) &
        ok "Generating wallpaper thumbnails in the background"
    fi
    echo ""
    exit 0
fi

# Interactive-only part: banner, package install, avatar note. --auto skips it —
# packages are guaranteed by the AUR dependency list, the avatar moves to the wizard.
if [[ "$AUTO_MODE" != true ]]; then

# ─── Header ──────────────────────────────────────────────────────────────────
clear; echo ""
echo "  ${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RST}"
echo "  ${BOLD}${CYAN}║            Welcome to Velumeron                         ║${RST}"
echo "  ${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RST}"
echo ""
echo "  This bootstrap prepares velumeron on a fresh system: packages,"
echo "  services, Hyprland wiring, monitors (automatic) and the shell."
echo "  Workspaces, apps, wallpaper and avatar are then configured in the"
echo "  setup wizard that opens with the shell."
echo ""
hr; echo ""

# ─── 0) Package installation ──────────────────────────────────────────────────
say "Package installation"

REQUIRED_PKGS=(
    hypridle hyprlock hyprpolkitagent
    quickshell rofi-wayland kitty
    wallust hypremoji
    mpv qt6-multimedia qt6-declarative cmake ninja   # native wallpaper engine (libmpv→QtQuick plugin)
    playerctl jq socat fastfetch tmux
    network-manager-applet gnome-keyring
    nextcloud-client localsend
    openrgb ddcutil grim hyprshot python
    zenity qt5ct qt6ct adw-gtk-theme
    brightnessctl wl-clipboard clipvault ffmpeg libnotify
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
    ok "Found ~/.face — will be shown in the bar's user widget."
else
    # Optional; the onboarding GUI offers a picker for it on first start.
    ok "No ~/.face avatar yet — the setup wizard will offer to add one."
fi

fi  # AUTO_MODE

# ─── 1.5) Seed user dir + environment ────────────────────────────────────────
# Must run BEFORE we start services — hypridle and friends look for config
# files in $VELUMERON_USER_DIR.
say "Setting up ~/.config/velumeron/"

# wallust symlink — wallust expects its config at ~/.config/wallust/
mkdir -p "$HOME/.config"   # pristine accounts may not have it yet
if [[ ! -e "$HOME/.config/wallust" ]]; then
    ln -sf "$VELUMERON_DIR/wallust" "$HOME/.config/wallust"
    ok "Linked ~/.config/wallust → velumeron/wallust"
fi
# hypridle / hyprlock symlinks under ~/.config/hypr/ are created by sync_templates

# Copy templates from the package into the user dir
sync_templates
ok "Seeded ~/.config/velumeron/ from package templates"

# Genuinely fresh install (this machine has never seen a version): flag the
# onboarding wizard. Without the marker the shell can't tell "fresh install
# whose monitors welcome just auto-configured" apart from "existing install
# updating into the versioned world" — both lack the stamp but have monitors.
# onboarding-state.py consumes the flag; mark-seen removes it.
if [[ ! -f "$VELUMERON_USER_DIR/gui/last-seen-version" ]]; then
    mkdir -p "$VELUMERON_USER_DIR/gui"
    touch "$VELUMERON_USER_DIR/gui/first-run-pending"
fi

# Write VELUMERON_DIR / VELUMERON_USER_DIR into systemd user environment
# (takes effect on next login; we already have them exported in this shell)
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/velumeron.conf" <<EOF
VELUMERON_DIR=$VELUMERON_DIR
VELUMERON_USER_DIR=$VELUMERON_USER_DIR
EOF
ok "Wrote ~/.config/environment.d/velumeron.conf"

# Also push them into the running systemd user session so child processes
# (services we start below) inherit them right away.
systemctl --user import-environment VELUMERON_DIR VELUMERON_USER_DIR 2>/dev/null || true

# ─── 2) Background services ───────────────────────────────────────────────────
# --auto runs BEFORE the Wayland session exists — autostart.lua starts every
# daemon in-session, so skip them here.
if [[ "$AUTO_MODE" != true ]]; then
say "Starting background services"

AUTOSTART_LUA="$VELUMERON_DIR/hypr.lua/modules/autostart.lua"

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
            notify-send -a "Velumeron" "⚠ Autostart failed" "$binary" 2>/dev/null || true
        fi
        return
    fi

    # Pick the target process name to look for in pgrep
    case "$binary" in
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
        notify-send -a "Velumeron" "⚠ Autostart failed" "$binary" 2>/dev/null || true
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
    "nm-applet"
    "systemctl --user start hyprpolkitagent"
    "gnome-keyring-daemon --start --components=secrets"
    "wl-paste --watch clipvault store"
    "$VELUMERON_DIR/assets/scripts/float-cascade.sh"
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

fi  # AUTO_MODE

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
# velumeron package (paths embedded inline). Back up any user-edited version.
_HYP_ENTRY="$HYPR_CONFIG/hyprland.lua"
_NEW_ENTRY=$(cat <<EOF
local base = "$VELUMERON_DIR/hypr.lua/"
VTL_DIR      = base:match("^(.*)/hypr%.lua/?$")
VTL_USER_DIR = "$VELUMERON_USER_DIR"
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
ok "Wrote ~/.config/hypr/hyprland.lua (→ $VELUMERON_DIR)"

# ─── 4) Monitor + Workspace bootstrap (non-interactive) ─────────────────────
# Monitors get their best mode automatically; everything else (workspaces,
# apps, wallpaper, avatar) is asked by the onboarding GUI on first shell start.
say "Monitor & Workspace setup"

if command -v hyprctl >/dev/null 2>&1 && hyprctl monitors -j >/dev/null 2>&1 \
   && ! grep -q 'hl\.monitor' "$USER_SETTINGS" 2>/dev/null; then
    bash "$VELUMERON_DIR/.setup/hyprland.sh" --autostart
    ok "Monitors auto-configured with their best settings."
elif grep -q 'hl\.monitor' "$USER_SETTINGS" 2>/dev/null; then
    ok "Monitors already configured — keeping the existing setup."
else
    ok "Monitors will be auto-configured on the first Hyprland start."
fi

mon1=""
mon2=""
if [[ -f "$USER_SETTINGS" ]]; then
    mon1=$(grep -oP '^mon1\s*=\s*"\K[^"]+' "$USER_SETTINGS" 2>/dev/null | head -1 || true)
    mon2=$(grep -oP '^mon2\s*=\s*"\K[^"]+' "$USER_SETTINGS" 2>/dev/null | head -1 || true)
fi
[[ -n "$mon1" ]] && ok "Primary monitor: $mon1"
[[ -n "$mon2" ]] && ok "Secondary monitor: $mon2"

# ─── 6) Launch the shell ─────────────────────────────────────────────────────
if [[ "$AUTO_MODE" != true ]]; then
say "Starting the shell"
# launch-shell.sh → QuickShell (bar, OSD, notifications, settings). Idempotent.
# (--auto: Hyprland hasn't started yet; autostart.lua launches the shell.)
if bash "$VELUMERON_DIR/assets/scripts/launch-shell.sh" >/dev/null 2>&1; then
    ok "Shell running."
else
    warn "Shell did not start cleanly — it will also start on the next Hyprland launch."
fi
fi  # AUTO_MODE

# ─── 9) Default wallpaper ─────────────────────────────────────────────────────
say "Setting default wallpaper"

DEFAULT_WP="$VELUMERON_DIR/assets/wallpaper/horizontal/wp_qUmiue_hor.jpg"
if [[ "$AUTO_MODE" == true && -f "$VELUMERON_USER_DIR/quickshell/wallpapers.json" ]]; then
    ok "Wallpaper already configured — keeping it."
elif [[ -f "$DEFAULT_WP" ]]; then
    bash "$VELUMERON_DIR/assets/scripts/wallpaper-set.sh" --no-showcase "$DEFAULT_WP"
    ok "Wallpaper set."
else
    warn "Default wallpaper not found: $DEFAULT_WP"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
hr
echo ""
echo "  ${BOLD}${GREEN}Velumeron is ready!${RST}"
echo ""
echo "  The setup wizard opens with the shell to configure workspaces, apps,"
echo "  wallpaper and avatar."
echo ""
echo "  To reconfigure later:"
echo "    ${DIM}Super + X${RST}                                – Settings (monitors, workspaces, …)"
echo "    ${DIM}~/.config/velumeron/.setup/hyprland.sh${RST}  – CLI fallback (e.g. over SSH)"
echo ""
