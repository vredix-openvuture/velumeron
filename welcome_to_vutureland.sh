#!/usr/bin/env bash
# Vutureland setup wizard.
#
#   welcome_to_vutureland.sh           Full interactive first-run setup
#   welcome_to_vutureland.sh --sync    Refresh package templates from
#                                      $VUTURELAND_DIR without touching user
#                                      state (use after a pacman/yay upgrade)

set -euo pipefail

: "${VUTURELAND_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
: "${VUTURELAND_USER_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/vutureland}"
export VUTURELAND_DIR VUTURELAND_USER_DIR
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

            if [[ ! -e "$user_path" ]]; then
                mkdir -p "$(dirname "$user_path")"
                cp "$file" "$user_path"
            elif [[ "$file" -nt "$user_path" ]]; then
                # Only overwrite if the user's copy hasn't been modified after
                # the package's mtime — i.e. no manual edits.
                mkdir -p "$(dirname "$user_path")"
                cp "$file" "$user_path"
            fi
        done < <(find "$src" -type f -print0)
    done

    # Make sure assets/, gui/ exist in user dir (wallust + gui write into these)
    mkdir -p "$VUTURELAND_USER_DIR/assets" "$VUTURELAND_USER_DIR/gui"

    # Seed initial wallust outputs from package defaults if missing
    for _f in "${_wallust_outputs[@]}"; do
        if [[ ! -f "$VUTURELAND_USER_DIR/$_f" && -f "$VUTURELAND_DIR/$_f" ]]; then
            mkdir -p "$(dirname "$VUTURELAND_USER_DIR/$_f")"
            cp "$VUTURELAND_DIR/$_f" "$VUTURELAND_USER_DIR/$_f"
        fi
    done
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
    echo ""
    echo "  Restart Hyprland or run  ${DIM}hyprctl reload${RST}  to pick up changes."
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

# ─── 2) Background services ───────────────────────────────────────────────────
say "Starting background services"

AUTOSTART_LUA="$VUTURELAND_DIR/hypr.lua/modules/autostart.lua"

# Kill existing instance and restart as background daemon.
_start_daemon() {
    local cmd_raw="$1"
    local cmd="${cmd_raw//\~/$HOME}"
    local first_word binary

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

    pkill -f "$binary" 2>/dev/null || true
    sleep 0.1

    eval "$cmd" &>/dev/null &
    local pid=$!
    disown "$pid" 2>/dev/null
    sleep 0.3
    if kill -0 "$pid" 2>/dev/null; then
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

# ── System daemons from autostart.lua ──────────────────
while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    _start_daemon "$cmd"
done < <(awk '
    /System daemons/ { in_s=1; next }
    /Device-specific|Cursor and shell/ { in_s=0 }
    in_s && /hl\.exec_cmd\(/ {
        s = $0
        sub(/.*hl\.exec_cmd\("/, "", s)
        sub(/".*$/, "", s)
        print s
    }
' "$AUTOSTART_LUA")

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
if [[ ! -f "$HYPR_CONFIG/hyprland.lua" ]]; then
    cat > "$HYPR_CONFIG/hyprland.lua" <<EOF
local base = "$VUTURELAND_DIR/hypr.lua/"
VTL_DIR      = base:match("^(.*)/hypr%.lua/?$")
VTL_USER_DIR = os.getenv("HOME") .. "/.config/vutureland"
package.path = base .. "?.lua;"
            .. base .. "modules/?.lua;"
            .. base .. "modules/?/init.lua;"
            .. package.path
dofile(base .. "hyprland.lua")
EOF
    ok "Created ~/.config/hypr/hyprland.lua (→ $VUTURELAND_DIR)"
else
    ok "~/.config/hypr/hyprland.lua already exists — skipping."
fi

# Write VUTURELAND_DIR into systemd user environment so Hyprland inherits it
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/vutureland.conf" <<EOF
VUTURELAND_DIR=$VUTURELAND_DIR
VUTURELAND_USER_DIR=$VUTURELAND_USER_DIR
EOF
ok "Wrote ~/.config/environment.d/vutureland.conf"

# wallust symlink — wallust expects its config at ~/.config/wallust/
if [[ ! -e "$HOME/.config/wallust" ]]; then
    ln -sf "$VUTURELAND_DIR/wallust" "$HOME/.config/wallust"
    ok "Linked ~/.config/wallust → vutureland/wallust"
fi

# Seed VUTURELAND_USER_DIR from the package — also strips obsolete symlinks
sync_templates
ok "Seeded ~/.config/vutureland/ from package templates"

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

# ─── 7) Apply default Waybar template ────────────────────────────────────────
say "Applying default Waybar layout"

OUTPUT_DIR="$VUTURELAND_DIR/waybar-modular/output"
TEMPLATE_DIR="$VUTURELAND_DIR/waybar-modular/templates"

apply_template() {
    local monitor="$1" tmpl_name="$2"
    local tmpl="$TEMPLATE_DIR/$tmpl_name/groups.json"
    local dest="$OUTPUT_DIR/dock/top/$monitor"
    if [[ ! -f "$tmpl" ]]; then
        warn "Template not found: $tmpl — skipping $monitor."
        return
    fi
    if [[ -d "$dest" ]]; then
        ok "Panel for $monitor already configured — skipping template."
        return
    fi
    mkdir -p "$dest"
    cp "$tmpl" "$dest/groups.json"
    ok "Applied '$tmpl_name' template → $monitor"
}

apply_template "$mon1" "primary"
[[ -n "$mon2" ]] && apply_template "$mon2" "secondary"

# ─── 8) Build + launch Waybar ────────────────────────────────────────────────
say "Building and launching Waybar"

bash "$VUTURELAND_DIR/.setup/waybar.sh" --rebuild
ok "Waybar running."

echo ""
if ask_yn "Customize Waybar modules now?" "y"; then
    bash "$VUTURELAND_DIR/.setup/waybar.sh"
fi

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
