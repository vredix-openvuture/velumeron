#!/usr/bin/env bash
# Velumeron – Quickshell Launcher
# Kills any running Quickshell instance and starts fresh.
# Quickshell reads from $VELUMERON_DIR/quickshell/ for QML sources.
# Colours are NOT generated into Colors.qml anymore — Colors.qml is a static reader that watches
# $VELUMERON_USER_DIR/quickshell/colors.json (written by wallust) and updates the palette live, so a
# theme change needs no restart. Nothing to sync here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

QS_PKG_DIR="$VELUMERON_DIR/quickshell"
QS_USER_DIR="$VELUMERON_USER_DIR/quickshell"
mkdir -p "$QS_USER_DIR"

# Drop any inherited file descriptors before (re)launching the long-lived shell. This script is
# also invoked by wallust's `qs_reload` hook, which runs *inside* a `flock`-held wallust (see
# wallpaper-set.sh). Without this, quickshell would inherit the still-open lock fd and hold the
# wallust lock for its whole lifetime — so every later wallpaper change hit `flock -n` busy and
# silently skipped the recolour. Closing fds 3–9 detaches us from that lock.
exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-

# Native wallpaper engine: the libmpv→QtQuick plugin (Velumeron.Mpv) lives under quickshell/plugins.
# Build it on first run, expose it via QML_IMPORT_PATH, and force the OpenGL scene-graph backend (mpv's
# render API needs GL, not Vulkan).
# Rebuild if EITHER the plugin OR its backing library is missing — the plugin links against
# libvelumeronmpv.so, so a present-but-orphaned plugin still fails to load and blacks out video
# wallpapers. Checking both makes a half-built state self-heal on the next launch.
_mpv_dir="$QS_PKG_DIR/plugins/Velumeron/Mpv"
if [[ ! -f "$_mpv_dir/libvelumeronmpvplugin.so" || ! -f "$_mpv_dir/libvelumeronmpv.so" ]]; then
    bash "$SCRIPT_DIR/build-mpv-plugin.sh" >/tmp/velumeron-mpv-build.log 2>&1 || \
        echo "warning: mpv plugin build failed (see /tmp/velumeron-mpv-build.log)" >&2
fi
export QML_IMPORT_PATH="$QS_PKG_DIR/plugins${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
export QSG_RHI_BACKEND=opengl

pkill -x quickshell 2>/dev/null || true
sleep 0.15

VELUMERON_DIR="$VELUMERON_DIR" \
VELUMERON_USER_DIR="$VELUMERON_USER_DIR" \
quickshell -p "$QS_PKG_DIR" > /tmp/quickshell-launch.log 2>&1 &
disown

echo "Quickshell started (pkg: $QS_PKG_DIR, colors: $QS_USER_DIR)"
