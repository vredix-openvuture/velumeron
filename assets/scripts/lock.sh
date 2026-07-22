#!/usr/bin/env bash
# Engages the native quickshell lockscreen by poking its `lock` IPC handler (shell.qml).
#
# Wired from hypridle's lock_cmd, so the chain is:
#   loginctl lock-session  →  logind emits Session.Lock  →  hypridle runs lock_cmd  →  here
# and also usable directly for testing. `qs -p` must match the path the running instance was
# launched with; env.sh resolves VELUMERON_DIR from this script's own location, so it lines up
# with launch-quickshell.sh (both installed → /usr/share/velumeron).
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

exec qs -p "$VELUMERON_DIR/quickshell" ipc call lock "${1:-lock}"
