#!/usr/bin/env bash
# Central path library — source this at the top of every vutureland script:
#
#   source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"
#
# VUTURELAND_DIR      — package/system directory (scripts, configs, assets)
#                       Auto-detected from this file's location. Can be
#                       overridden by setting the env var before sourcing.
# VUTURELAND_USER_DIR — per-user data (generated output, user_settings, prefs)
#                       Always ${XDG_CONFIG_HOME:-~/.config}/vutureland.

if [[ -z "${VUTURELAND_DIR:-}" ]]; then
    VUTURELAND_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
fi
export VUTURELAND_DIR

VUTURELAND_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/vutureland"
export VUTURELAND_USER_DIR
