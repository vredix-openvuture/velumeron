#!/usr/bin/env bash
# idle-suspend.sh — hypridle's suspend target (instead of a bare `systemctl suspend`).
# Suspends only when the machine is genuinely idle. A plain idle timer fires right
# through a HandBrake encode or a long build: "no input" is not "no work". Skipped
# suspends are logged to the journal (tag: velumeron-idle).
#
# Note: hypridle fires on-timeout once per idle period — a skipped suspend is not
# retried until the next activity→idle cycle. That is intentional: better a machine
# that stays on than one that suspends mid-encode.

skip() {
    logger -t velumeron-idle "suspend skipped: $1" 2>/dev/null || true
    exit 0
}

# 1) Application/system BLOCK inhibitors for sleep or idle (systemd-inhibit runs,
#    inhibiting media players, …). The standard delay inhibitors (NetworkManager,
#    UPower, hypridle itself) don't count.
if systemd-inhibit --list --no-pager 2>/dev/null \
    | awk '$NF == "block"' | grep -qE 'sleep|idle'; then
    skip "active sleep/idle block inhibitor"
fi

# 2) Real CPU work — encodes, compiles, renders (HandBrake does not manage to
#    place an inhibitor on this stack). Measured over a 1s /proc/stat sample:
#    loadavg lags minutes behind and misses a freshly started encode.
read -r _ u1 n1 s1 i1 w1 x1 y1 z1 _ < /proc/stat
sleep 1
read -r _ u2 n2 s2 i2 w2 x2 y2 z2 _ < /proc/stat
busy=$(( (u2 + n2 + s2 + x2 + y2 + z2) - (u1 + n1 + s1 + x1 + y1 + z1) ))
idle=$(( (i2 + w2) - (i1 + w1) ))
total=$(( busy + idle ))
pct=$(( total > 0 ? busy * 100 / total : 0 ))
if [ "$pct" -gt 15 ]; then
    skip "cpu ${pct}% busy"
fi

# 3) Audio playing (music, calls, videos)
if command -v pactl >/dev/null 2>&1 && pactl list short sinks 2>/dev/null | grep -q RUNNING; then
    skip "audio playing"
fi

exec systemctl suspend
