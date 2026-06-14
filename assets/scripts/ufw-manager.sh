#!/usr/bin/env bash
# Vutureland — UFW Firewall Manager launcher
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

exec python3 "$VUTURELAND_DIR/gui/ufw_manager.py" "$@"
