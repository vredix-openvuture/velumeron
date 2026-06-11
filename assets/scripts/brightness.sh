#!/usr/bin/env bash
# Vutureland – brightness control with OSD feedback.
#
# Prefers brightnessctl when a real /sys/class/backlight device exists (laptop
# panels — instant). Otherwise falls back to ddcutil for external monitors over
# DDC/CI, targeting cached I2C buses directly (`--bus`) so each step is ~0.3s
# instead of ~2s (ddcutil's per-call display detection is the slow part).
# Brightness moves in 5% steps, clamped to 0–100.
#
#   brightness.sh up      # +5%
#   brightness.sh down    # -5%
#   brightness.sh warm    # pre-build the DDC bus cache (run at autostart)

set -u

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
OSD="$SCRIPT_DIR/osd-show.sh"
STEP=5
ARG="${1:-up}"

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
BUS_CACHE="$RUNTIME/vutureland-ddc-buses"     # cached DDC-capable I2C buses
STATE="$RUNTIME/vutureland-brightness"        # last known DDC brightness %
INC_LOCK="$RUNTIME/vutureland-brightness.inc.lock"     # serialises target bumps
APPLY_LOCK="$RUNTIME/vutureland-brightness.apply.lock"  # single-flight DDC writer

have_backlight() {
    command -v brightnessctl >/dev/null 2>&1 || return 1
    compgen -G "/sys/class/backlight/*" >/dev/null 2>&1
}

# DDC-capable I2C buses. `ddcutil detect` is slow, so probe once and cache the
# buses that actually answer; later calls just read the cache.
ddc_buses() {
    if [[ -s "$BUS_CACHE" ]]; then cat "$BUS_CACHE"; return; fi
    local b valid=()
    for b in $(ddcutil detect --terse 2>/dev/null | grep -oP '/dev/i2c-\K[0-9]+'); do
        ddcutil --bus "$b" --noverify getvcp 10 >/dev/null 2>&1 && valid+=("$b")
    done
    (( ${#valid[@]} )) && printf '%s\n' "${valid[@]}" > "$BUS_CACHE"
    printf '%s\n' "${valid[@]}"
}

clamp() { local v=$1; (( v > 100 )) && v=100; (( v < 0 )) && v=0; echo "$v"; }

# warm: just populate the bus cache so the first real keypress is already fast.
if [[ "$ARG" == warm ]]; then
    have_backlight || ddc_buses >/dev/null
    exit 0
fi

delta=$STEP
[[ "$ARG" == down ]] && delta=$(( -STEP ))

# ── brightnessctl (real backlight) ──────────────────────────────────────────
if have_backlight; then
    if (( delta >= 0 )); then brightnessctl set "${STEP}%+" >/dev/null 2>&1
    else                      brightnessctl set "${STEP}%-" >/dev/null 2>&1; fi
    cur=$(brightnessctl -m 2>/dev/null | awk -F, '{print $4}' | tr -d '%')
    "$OSD" brightness "${cur:-0}"
    exit 0
fi

# ── ddcutil fallback (external monitors, bus-direct) ────────────────────────
mapfile -t BUSES < <(ddc_buses)
(( ${#BUSES[@]} )) || exit 0   # no DDC-capable monitor

# Bump the target atomically so held-key repeats (concurrent invocations) don't
# lose steps. Seed from the monitor only when no state exists yet.
exec 8>"$INC_LOCK"
flock 8
cur=$(cat "$STATE" 2>/dev/null)
if [[ ! "$cur" =~ ^[0-9]+$ ]]; then
    cur=$(ddcutil --bus "${BUSES[0]}" --noverify getvcp 10 2>/dev/null \
          | grep -oP 'current value =\s*\K[0-9]+')
fi
[[ "$cur" =~ ^[0-9]+$ ]] || cur=100
new=$(clamp $(( cur + delta )))
echo "$new" > "$STATE"
exec 8>&-

"$OSD" brightness "$new"        # instant feedback, before the I2C writes land

# Single-flight applier: coalesces a burst of held-key repeats into the latest
# target. One worker writes until the value stops moving; concurrent invocations
# bail (this worker already covers their bump) so slow I2C writes never queue up.
{
    exec 9>"$APPLY_LOCK"
    flock -n 9 || exit 0
    last=""
    while :; do
        target=$(cat "$STATE" 2>/dev/null)
        [[ "$target" == "$last" ]] && break
        last="$target"
        for b in "${BUSES[@]}"; do
            ddcutil --bus "$b" --noverify setvcp 10 "$target" >/dev/null 2>&1 &
        done
        wait
    done
} &
disown
