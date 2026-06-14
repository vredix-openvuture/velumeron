#!/usr/bin/env bash
# Vutureland – OSD daemon launcher.
# Restarts the brightness/volume OSD daemon (single instance).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

OSD_PY="$VUTURELAND_DIR/gui/osd.py"

# Drop a stale FIFO and any previous instance before starting fresh.
pkill -f "$OSD_PY" 2>/dev/null || true
sleep 0.2

# gtk4-layer-shell must be loaded before libwayland-client, which the dynamic
# linker only guarantees via LD_PRELOAD (see the project's linking notes).
for lib in /usr/lib/libgtk4-layer-shell.so /usr/lib64/libgtk4-layer-shell.so; do
    [[ -e "$lib" ]] && { export LD_PRELOAD="$lib"; break; }
done

exec python -u "$OSD_PY" > /tmp/vutureland-osd.log 2>&1
