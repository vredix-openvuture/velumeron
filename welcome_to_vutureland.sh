#!/usr/bin/env bash
# First-run setup wizard for vutureland.
# Run once after cloning on a fresh system.

set -euo pipefail

VUTURELAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_SETTINGS="$VUTURELAND_DIR/hypr/user_settings.conf"

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

killall -q swaync 2>/dev/null || true
swaync -c "$VUTURELAND_DIR/swaync/config.json" \
       -s "$VUTURELAND_DIR/swaync/style.css" &
disown
ok "swaync"

if ! pgrep -x awww-daemon &>/dev/null; then
    awww-daemon &
    disown
    sleep 0.5
fi
ok "awww-daemon"

killall -q hypridle 2>/dev/null || true
hypridle -c "$VUTURELAND_DIR/hypr.lua/hypridle.conf" &
disown
ok "hypridle"

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
if [[ ! -f "$HYPR_CONFIG/hyprland.conf" ]]; then
    printf 'source = ~/.config/vutureland/hypr.lua/hyprland.lua\n' \
        > "$HYPR_CONFIG/hyprland.conf"
    ok "Created ~/.config/hypr/hyprland.conf"
else
    ok "~/.config/hypr/hyprland.conf already exists — skipping."
fi

# wallust symlink
if [[ ! -e "$HOME/.config/wallust" ]]; then
    ln -sf "$VUTURELAND_DIR/wallust" "$HOME/.config/wallust"
    ok "Linked ~/.config/wallust → vutureland/wallust"
fi

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
    mon1=$(grep -oP '^\$mon1\s*=\s*\K\S+' "$USER_SETTINGS" 2>/dev/null | head -1 || true)
    mon2=$(grep -oP '^\$mon2\s*=\s*\K\S+' "$USER_SETTINGS" 2>/dev/null | head -1 || true)
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
