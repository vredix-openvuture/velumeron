#!/usr/bin/env bash
# build-mpv-plugin.sh — configure + build the libmpv→QtQuick wallpaper plugin (Velumeron.Mpv).
# Idempotent: re-running just rebuilds what changed. The compiled QML module lands in
# quickshell/plugins/Velumeron/Mpv/ ; launch-quickshell.sh adds quickshell/plugins to QML_IMPORT_PATH.
set -euo pipefail
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

src="$VELUMERON_DIR/quickshell/plugins/mpv"
build="$src/build"

cmake -S "$src" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$build"
echo "Built Velumeron.Mpv → $VELUMERON_DIR/quickshell/plugins/Velumeron/Mpv"
