#!/usr/bin/env bash
# Hand the chosen UI style to Hyprland.
#
#   apply-ui-style.sh <style>
#
# hyprland.lua reads <USER_DIR>/active-theme and dofiles hypr.lua/themes/<style>.lua, which
# overrides the window decoration (border colour, rounding_power, glow, shadow, blur, gaps) to match
# the shell look. Rounding/border_size stay user-controlled (Look & Feel page) — the theme files use
# them as `lnf_rounding or <default>`. A missing theme file is a no-op: the base look_and_feel stands.
#
# Note: window corners can only be rounded (or squircled via rounding_power) — Hyprland can't chamfer,
# scallop or wobble a window edge, so those styles approximate the vibe on windows, not the silhouette.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

style="${1:-flat}"
mkdir -p "$VELUMERON_USER_DIR"
printf '%s\n' "$style" > "$VELUMERON_USER_DIR/active-theme"

# Re-read the whole Hyprland config so look_and_feel + themes/<style>.lua re-apply. Cheap and
# idempotent; harmless if Hyprland isn't running (e.g. applying from a TTY).
hyprctl reload >/dev/null 2>&1 || true
