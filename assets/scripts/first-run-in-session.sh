#!/usr/bin/env bash
# Bring velumeron up inside an ALREADY RUNNING Hyprland session — the other half of
# post-install-handoff.sh, and the reason a fresh install needs no re-login.
#
# Runs as the user, with WAYLAND_DISPLAY / HYPRLAND_INSTANCE_SIGNATURE / XDG_RUNTIME_DIR
# already set by the caller. Also usable by hand:  bash first-run-in-session.sh
#
# Order matters:
#   1. bootstrap (--auto, non-interactive) writes ~/.config/velumeron and ~/.config/hypr/hyprland.lua
#   2. hyprctl reload  → the compositor picks up the velumeron config
#   3. services        → autostart.lua only runs them at compositor START, so a live
#                        reload would leave them down; start them explicitly
#   4. the shell       → quickshell, which opens the onboarding wizard on a first run
set -uo pipefail

VELUMERON_DIR="${VELUMERON_DIR:-/usr/share/velumeron}"
export VELUMERON_DIR
export VELUMERON_USER_DIR="${VELUMERON_USER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/velumeron}"

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/velumeron-first-run.log"
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "── first run in session: $(date -Is) ──"

bash "$VELUMERON_DIR/welcome_to_velumeron.sh" --auto || true

hyprctl reload || true

bash "$VELUMERON_DIR/assets/scripts/velumeron-services.sh" start || true

# The shell brings the wizard with it; launch-quickshell.sh replaces a running instance,
# so this is safe whether or not something is already up.
bash "$VELUMERON_DIR/assets/scripts/launch-quickshell.sh" || true

echo "── done ──"
