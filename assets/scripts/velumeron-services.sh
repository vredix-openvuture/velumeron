#!/usr/bin/env bash
# Velumeron — session service supervisor.
#
# Single source of truth for the daemons + shell that make up a Velumeron
# session. Used by:
#   • hypr.lua autostart (on hyprland.start)  → velumeron-services.sh start
#   • bin/velumeron start / end               → start / stop
#
# start is idempotent (skips services that are already up), stop is best-effort.
# Both are safe to run repeatedly.
#
#   velumeron-services.sh start | stop | restart | status
#
# NOTE: device-specific daemons (exec_once_daemons) and workspace startup apps
# (start_apps) are user-config-driven and stay in autostart.lua — they are not
# "our services" and are intentionally NOT managed here.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

# ── Service table ────────────────────────────────────────────────────────────
# One entry per service: "label|check|start|stop"
#   check — succeeds (exit 0) when the service is already running
#   start — command to launch it (run detached, see start_svc)
#   stop  — command to shut it down (best-effort)
# Fields are split on '|'; no snippet below may contain a literal '|'.
SERVICES=(
    # -c is not optional: hypridle otherwise looks only in ~/.config/hypr, which reaches our config
    # through a symlink the installer seeds. A dangling link there (the trailer pipeline re-pointed
    # it at its throwaway profile on 2026-08-16 and the profile was deleted) makes the daemon exit
    # at every login with "no config", and with it the logind bridge — lock-session, before-sleep,
    # resume-wake — goes away silently. Naming the file removes that whole failure mode.
    "hypridle|pgrep -x hypridle|hypridle -c \"$VELUMERON_USER_DIR/hypr.lua/hypridle.conf\"|pkill -x hypridle"
    "lid-inhibit|pgrep -f 'systemd-inhibit.*handle-lid-switch'|systemd-inhibit --what=handle-lid-switch --who=velumeron --why='Hyprland handles the lid' --mode=block sleep infinity|pkill -f 'systemd-inhibit.*handle-lid-switch'"
    "nm-applet|pgrep -x nm-applet|nm-applet|pkill -x nm-applet"
    "polkit|systemctl --user is-active --quiet hyprpolkitagent|systemctl --user start hyprpolkitagent|systemctl --user stop hyprpolkitagent"
    "keyring|pgrep -x gnome-keyring-d|gnome-keyring-daemon --start --components=secrets|pkill -x gnome-keyring-d"
    # ONE-SHOT: `warm` pre-builds the DDC bus cache and exits, so there is no process to find
    # afterwards. `check` is deliberately false-forever (it never matches) — before the start check
    # below existed that only made the status table say "down"; now it would claim a failure, so it
    # is spelled out as a one-shot instead: run it every time, never expect it to stay up.
    "brightness|false|bash $VELUMERON_DIR/assets/scripts/brightness.sh warm|true"
    "clipvault|pgrep -f 'wl-paste --watch clipvault'|wl-paste --watch clipvault store|pkill -f 'wl-paste --watch clipvault'"
    "float-cascade|pgrep -f float-cascade.sh|bash $VELUMERON_DIR/assets/scripts/float-cascade.sh|pkill -f float-cascade.sh"
    # Lighting. A no-op unless Settings → Integrations switched OpenRGB on AND a startup profile is
    # picked — `boot` checks both and exits. Stop is deliberately `true`: the user may have opened
    # OpenRGB themselves, and killing it would not turn the lights off anyway (the hardware keeps
    # the last colours), so ending the session has nothing to undo here.
    "openrgb|pgrep -x openrgb|bash $VELUMERON_DIR/assets/scripts/openrgb.sh boot|true"
    "shell|pgrep -x quickshell|bash $VELUMERON_DIR/assets/scripts/launch-shell.sh|pkill -x quickshell"
)

_field() { local IFS='|'; read -r -a f <<< "$1"; printf '%s' "${f[$2]}"; }
log()    { printf '  %-14s %s\n' "$1" "$2"; }

start_svc() {
    local label="$1" check="$2" start="$3"
    # Kill switch. `touch ~/.velumeron-no-shell` and the shell stays down at login, so a session
    # that cannot survive the shell coming up still gives you a usable desktop and a terminal to
    # debug from. Everything else — hypridle, polkit, clipboard, brightness — starts as normal.
    # Delete the file to get the shell back.
    if [[ "$label" == "shell" && -e "$HOME/.velumeron-no-shell" ]]; then
        log "$label" "SKIPPED (~/.velumeron-no-shell exists)"
        return
    fi
    if eval "$check" >/dev/null 2>&1; then
        log "$label" "already running"
        return
    fi
    # setsid -f detaches from the controlling terminal and its own session, so
    # foreground daemons (hypridle, nm-applet, brightness, clipvault,
    # float-cascade) survive `velumeron start` returning / the terminal closing.
    # Self-daemonising / one-shot commands (keyring, systemctl, launch-shell)
    # simply exit inside it — harmless.
    setsid -f bash -c "$start" >/dev/null 2>&1
    # "started" used to mean "the command was launched", which is not the same thing: a daemon that
    # dies on a bad config exits within milliseconds and the table still reported it as up. Give it
    # a beat and ask the check again, so a service that refuses to run says so at login.
    # One-shots (check = false) have nothing to still be running; everything else is asked again.
    if [[ "$check" == "false" ]]; then
        log "$label" "ran"
        return
    fi
    sleep 0.4
    if eval "$check" >/dev/null 2>&1; then
        log "$label" "started"
    else
        log "$label" "FAILED to stay up — run its start command by hand to see why"
    fi
}

stop_svc() {
    local label="$1" stop="$4"
    eval "$stop" >/dev/null 2>&1 || true
    log "$label" "stopped"
}

status_svc() {
    local label="$1" check="$2"
    # A one-shot has no process to look for; "down" would read as broken.
    if [[ "$check" == "false" ]]; then
        log "$label" "one-shot"
        return
    fi
    if eval "$check" >/dev/null 2>&1; then
        log "$label" "up"
    else
        log "$label" "down"
    fi
}

for_each() {                       # for_each <fn> [reverse]
    local fn="$1" i
    if [[ "${2:-}" == reverse ]]; then
        for (( i=${#SERVICES[@]}-1; i>=0; i-- )); do
            "$fn" "$(_field "${SERVICES[$i]}" 0)" "$(_field "${SERVICES[$i]}" 1)" \
                  "$(_field "${SERVICES[$i]}" 2)" "$(_field "${SERVICES[$i]}" 3)"
        done
    else
        for i in "${SERVICES[@]}"; do
            "$fn" "$(_field "$i" 0)" "$(_field "$i" 1)" "$(_field "$i" 2)" "$(_field "$i" 3)"
        done
    fi
}

case "${1:-}" in
    start)   echo "Velumeron services — starting:"; for_each start_svc ;;
    stop)    echo "Velumeron services — stopping:"; for_each stop_svc reverse ;;
    restart) "$0" stop; sleep 0.3; "$0" start ;;
    status)  echo "Velumeron services:";            for_each status_svc ;;
    *)       echo "usage: velumeron-services.sh start|stop|restart|status" >&2; exit 2 ;;
esac
