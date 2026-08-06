#!/usr/bin/env bash
# suspend.sh — lock FIRST, wait until the lockscreen has actually drawn, THEN suspend.
#
# A bare `systemctl suspend` races the lock. The chain is: logind emits PrepareForSleep →
# hypridle runs before_sleep_cmd (loginctl lock-session) and, with inhibit_sleep=3, holds the
# delay inhibitor until the compositor reports the ext-session-lock ACTIVE. "Active" means the
# lock surfaces exist — NOT that they have painted. The screen went down while the lockscreen was
# still assembling (pre-lock screenshot, blurred wallpaper decode, iris reveal), so you got a
# half-built lock on resume.
#
# The shell touches $READY once its lock surfaces are up and the reveal has played
# (quickshell/lock/Lock.qml); we poll for it and only then suspend. TIMEOUT caps the wait so a
# dead, disabled or standalone-less shell can never keep the machine awake — after the cap we
# suspend regardless (the session is locked by logind by then either way).
#
# Used by the session menu / User glide / home hub (UiState.sessionActions), the lid handler and
# the idle path, so every route through "suspend" gets the same sequencing. Deliberately does NOT
# source lib/env.sh: the suspend path stays free of jq/subshell work, and nothing here needs
# $VELUMERON_DIR.

READY="${XDG_RUNTIME_DIR:-/tmp}/velumeron-lock-ready"
TIMEOUT="${VELUMERON_LOCK_WAIT:-5}"     # seconds to wait for the lockscreen at most
STEP=0.05

# Already locked and drawn (e.g. the idle path locked minutes ago) → nothing to wait for.
if [[ ! -e "$READY" ]]; then
    loginctl lock-session

    ticks=$(( ${TIMEOUT%.*} * 20 ))
    for ((i = 0; i < ticks; i++)); do
        [[ -e "$READY" ]] && break
        sleep "$STEP"
    done
    [[ -e "$READY" ]] || logger -t velumeron-suspend \
        "lockscreen not ready after ${TIMEOUT}s — suspending anyway" 2>/dev/null || true
fi

# One more frame on screen before the outputs go: the flag is written from the shell's event loop,
# the compositor still has to present that frame.
sleep 0.2

exec systemctl suspend
