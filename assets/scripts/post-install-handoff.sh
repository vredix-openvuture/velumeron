#!/usr/bin/env bash
# Hand a fresh install over to the Hyprland session it was installed FROM.
#
# The normal case is someone already sitting in Hyprland who opens a terminal and installs
# velumeron. Nothing about that situation needs a re-login: the compositor is up, so the
# bootstrap can run, Hyprland can reload onto the velumeron config, and the shell (with the
# onboarding wizard inside it) can start — while the terminal they typed in is still open.
#
# Called by the package's post_install, therefore as ROOT and mid-transaction. That means:
#   - the real user comes from SUDO_USER (yay/paru run pacman through sudo)
#   - everything user-facing is re-entered through `sudo -u`, with the session environment
#     reconstructed from /run/user/<uid> (pacman's own env has none of it)
#   - the work is detached with setsid, so pacman is never left waiting on a desktop
#   - EVERY failure path exits 0: a package must not break because a desktop hand-off
#     did not work out (chroot, container, SSH, no session, another compositor).
#
# Exit 0 + no output = nothing was done; the caller prints the manual fallback then.
set -uo pipefail

VELUMERON_DIR="${VELUMERON_DIR:-/usr/share/velumeron}"

user="${SUDO_USER:-${PACMAN_CALLER:-}}"
[[ -n "$user" && "$user" != "root" ]] || exit 0
uid="$(id -u "$user" 2>/dev/null)" || exit 0
run="/run/user/$uid"
[[ -d "$run" ]] || exit 0

# A Hyprland session of that user, right now? Its instance signature is a directory under
# $XDG_RUNTIME_DIR/hypr; the newest one is the session the terminal belongs to.
sig="$(ls -t "$run/hypr" 2>/dev/null | head -n1)"
[[ -n "$sig" ]] || exit 0

# The wayland socket next to it (wayland-1, wayland-0, …) — needed by anything Qt/GTK.
wl=""
for s in "$run"/wayland-[0-9]*; do
    [[ -S "$s" ]] || continue
    wl="$(basename "$s")"
    break
done
[[ -n "$wl" ]] || exit 0

echo "  Hyprland session of '$user' found — setting up in place, no re-login needed."

# Detached, as the user, with the session environment rebuilt. `setsid` cuts it loose from
# pacman's process group so the transaction finishes immediately.
setsid -f sudo -u "$user" env \
    HOME="$(getent passwd "$user" | cut -d: -f6)" \
    XDG_RUNTIME_DIR="$run" \
    WAYLAND_DISPLAY="$wl" \
    HYPRLAND_INSTANCE_SIGNATURE="$sig" \
    VELUMERON_DIR="$VELUMERON_DIR" \
    bash "$VELUMERON_DIR/assets/scripts/first-run-in-session.sh" \
    >/dev/null 2>&1 || true

exit 0
