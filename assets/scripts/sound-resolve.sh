#!/usr/bin/env bash
# Resolve every sound event to a playable file and print "<key><TAB><path>", one per line.
#
# Why a resolver at all: the catalogue in SoundService.qml names EVENTS ("login"), while the files
# on disk are named by whatever convention their theme uses ("service-login.oga"), in one of three
# places. Something has to map one onto the other, and doing it in shell means the same answer is
# available to the session scripts, which have no access to the shell's state.
#
# No conversion step: playback goes through paplay, which reads Vorbis, FLAC and WAV alike. (An
# earlier version decoded everything to WAV because the in-process engine only took PCM. That
# engine is gone — see SoundService.qml — and the cache went with it.)
#
# Search order per event, first hit wins:
#   1. $VELUMERON_USER_DIR/sounds/<key>.*   — the user's own file, always beats everything
#   2. the active pack                      — assets/sounds/<pack>/<key>.*
#   3. the freedesktop theme                — /usr/share/sounds/<theme>/stereo/<fd-name>.oga
# The fallback is what makes a half-finished pack usable: an event the pack has no file for still
# makes a sound instead of silently doing nothing, and "why is this one silent" never comes up.
#
# Usage:  sound-resolve.sh <pack> <key>:<fd-name> [<key>:<fd-name> …]
# Output: only the events that resolved. A missing event is simply absent — the caller treats
#         "no path" as "stay quiet", so a stripped-down system is never an error.

set -uo pipefail

PACK="${1:-freedesktop}"
shift || true

USER_DIR="${VELUMERON_USER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/velumeron}"
PKG_DIR="${VELUMERON_DIR:-/usr/share/velumeron}"
FD_THEME="${VELUMERON_SOUND_THEME:-freedesktop}"

# Extensions we accept as a source. paplay reads all of them; the order only decides which one
# wins if someone drops two files with the same stem.
EXTS=(wav ogg oga flac opus mp3)

# First existing file among <dir>/<stem>.<ext> for every ext we accept.
find_src() {
    local dir="$1" stem="$2" ext
    for ext in "${EXTS[@]}"; do
        [[ -f "$dir/$stem.$ext" ]] && { printf '%s\n' "$dir/$stem.$ext"; return 0; }
    done
    return 1
}

# Everything resolved is ALSO written to a lookup map in the runtime dir. That is what lets a sound
# be played by something that is not the shell — the logout sound, which by definition rings after
# the shell is gone (play-sound.sh reads it). The map means there is still exactly ONE event
# catalogue, the one in SoundService.qml: nothing else ever has to know that "logout" comes from a
# file called service-logout.oga. $XDG_RUNTIME_DIR is deleted with the session, so it cannot go stale.
MAP="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/velumeron-sounds.map"
: > "$MAP" 2>/dev/null || MAP=/dev/null

emit() { printf '%s\t%s\n' "$1" "$2"; printf '%s\t%s\n' "$1" "$2" >> "$MAP" 2>/dev/null || true; }

for pair in "$@"; do
    key="${pair%%:*}"
    fd="${pair#*:}"
    [[ -n "$key" ]] || continue

    src=""
    src=$(find_src "$USER_DIR/sounds" "$key")                     || true
    [[ -z "$src" && "$PACK" != "freedesktop" ]] && \
        src=$(find_src "$PKG_DIR/assets/sounds/$PACK" "$key")     || true
    if [[ -z "$src" && -n "$fd" ]]; then
        for base in "$USER_DIR/sounds/$FD_THEME/stereo" \
                    "/usr/share/sounds/$FD_THEME/stereo" \
                    "/usr/local/share/sounds/$FD_THEME/stereo"; do
            src=$(find_src "$base" "$fd") && break || true
        done
    fi
    [[ -n "$src" ]] || continue

    emit "$key" "$src"
done
