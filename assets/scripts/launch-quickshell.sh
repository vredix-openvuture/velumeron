#!/usr/bin/env bash
# Vutureland – Quickshell Launcher
# Kills any running Quickshell instance and starts fresh.
# Quickshell reads from $VUTURELAND_DIR/quickshell/ for QML sources.
# Wallust-generated Colors.qml lands in $VUTURELAND_USER_DIR/quickshell/Colors.qml
# and is preferred via the extra import path (-I flag).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

QS_PKG_DIR="$VUTURELAND_DIR/quickshell"
QS_USER_DIR="$VUTURELAND_USER_DIR/quickshell"

# Sync Colors.qml:
# - User dir (wallust target) → package dir (what Quickshell actually loads)
# - If user dir doesn't have one yet, seed it from the package default
mkdir -p "$QS_USER_DIR"
if [[ -f "$QS_USER_DIR/Colors.qml" ]]; then
    cp -f "$QS_USER_DIR/Colors.qml" "$QS_PKG_DIR/Colors.qml"
else
    cp "$QS_PKG_DIR/Colors.qml" "$QS_USER_DIR/Colors.qml"
fi

pkill -x quickshell 2>/dev/null || true
sleep 0.15

# -p  : project root (QML sources from package)
# -I  : extra import path (user Colors.qml overrides the package default)
VUTURELAND_DIR="$VUTURELAND_DIR" \
VUTURELAND_USER_DIR="$VUTURELAND_USER_DIR" \
quickshell -p "$QS_PKG_DIR" > /tmp/quickshell-launch.log 2>&1 &
disown

echo "Quickshell started (pkg: $QS_PKG_DIR, colors: $QS_USER_DIR)"
