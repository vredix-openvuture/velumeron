#!/usr/bin/env bash
# Play one shell sound and WAIT for it to finish. For the events the shell cannot play itself.
#
# The logout sound is the whole reason this exists: by the time the session is going down, the
# shell is being killed, and a sound started inside it dies mid-note. So the session action plays
# it here instead, synchronously, before it pulls the trigger.
#
# It knows nothing about which file an event maps to — it reads the map sound-resolve.sh leaves in
# the runtime dir. One event catalogue (SoundService.qml), and this stays honest with it for free.
# No map (the shell never ran) ⇒ silence, not a guess.
#
# Usage: play-sound.sh <event-key> [max-seconds]

set -uo pipefail

KEY="${1:-}"
MAXWAIT="${2:-4}"
[[ -n "$KEY" ]] || exit 0

MAP="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/velumeron-sounds.map"
[[ -r "$MAP" ]] || exit 0

USER_DIR="${VELUMERON_USER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/velumeron}"
SETTINGS="$USER_DIR/gui/settings.json"

# Same defaults as VtlConfig, so this cannot disagree with the UI: sounds on unless switched off,
# volume 60, an event on unless its own entry says otherwise. jq is optional — without it we take
# the defaults rather than refusing to make a sound.
vol=60
if [[ -r "$SETTINGS" ]] && command -v jq >/dev/null 2>&1; then
    [[ "$(jq -r '.component_enabled.sounds // true' "$SETTINGS" 2>/dev/null)" == "false" ]] && exit 0
    [[ "$(jq -r --arg k "$KEY" '.sound_events[$k] // true' "$SETTINGS" 2>/dev/null)" == "false" ]] && exit 0
    v=$(jq -r '.sound_volume // 60' "$SETTINGS" 2>/dev/null)
    [[ "$v" =~ ^[0-9]+$ ]] && vol="$v"
fi
(( vol > 0 )) || exit 0

path=$(awk -F'\t' -v k="$KEY" '$1 == k { print $2; exit }' "$MAP")
[[ -n "$path" && -r "$path" ]] || exit 0

# PulseAudio's scale, where 65536 is 100 % — the same one SoundService passes, so the slider means
# the same loudness whether the shell or this script is playing.
pavol=$(awk -v v="$vol" 'BEGIN { printf "%d", (v/100)*65536 }')

# --client-name matters as much as the sound: it puts this under the SAME mixer entry the shell
# uses, so "Velumeron" is one line in the mixer with one remembered level, not two that disagree
# depending on who happened to play.
# Capped: a sound must never be the reason a logout appears to hang. Whatever has not played by
# then is cut off, which is still better than a session that sits there.
if command -v paplay >/dev/null 2>&1; then
    timeout "$MAXWAIT" paplay --client-name=Velumeron --stream-name="$KEY" \
                              --volume="$pavol" "$path" >/dev/null 2>&1
elif command -v pw-play >/dev/null 2>&1; then
    timeout "$MAXWAIT" pw-play --volume="$(awk -v v="$vol" 'BEGIN{printf "%.3f", v/100}')" "$path" >/dev/null 2>&1
fi
exit 0
