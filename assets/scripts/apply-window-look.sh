#!/usr/bin/env bash
# Hand the chosen THEME to Hyprland.
#
#   apply-window-look.sh <theme-id>
#
# hyprland.lua reads <USER_DIR>/active-theme and dofiles hypr.lua/themes/<id>.lua, which overrides
# the window decoration (border colour, glow, shadow, blur, gaps, rounding_power) to match the shell
# look. Rounding/border_size stay user-controlled (Look & Feel page): the theme files use them as
# `lnf_rounding or <default>`. A missing theme file is a no-op — the base look_and_feel stands.
#
# The theme decides, not the ui_style. Both used to write this file and the later writer won, which
# is how a mirobo desk ended up running the `flat` frame: mirobo's arrangement sets ui_style=flat.
#
# Note: window corners can only be rounded (or squircled via rounding_power) — Hyprland can't chamfer,
# scallop or wobble a window edge, so those styles approximate the vibe on windows, not the silhouette.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

theme="${1:-flat}"
mkdir -p "$VELUMERON_USER_DIR"
file="$VELUMERON_USER_DIR/active-theme"

previous="$(cat "$file" 2>/dev/null || true)"
printf '%s\n' "$theme" > "$file"

# The shell hands the theme over on every start, not only on a switch, so the file heals itself
# after an upgrade. Reloading for a value Hyprland already runs would make that a visible cost.
[[ "$previous" == "$theme" ]] && exit 0

# Re-read the whole Hyprland config so look_and_feel + themes/<id>.lua re-apply. Cheap and
# idempotent; harmless if Hyprland isn't running (e.g. applying from a TTY).
hyprctl reload >/dev/null 2>&1 || true
