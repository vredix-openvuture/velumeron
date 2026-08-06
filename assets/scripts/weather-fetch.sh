#!/usr/bin/env bash
# Fetch the current weather (+ an optional multi-day outlook) for the lockscreen widget and write a
# compact JSON the shell watches.
#
#   weather-fetch.sh "<city>" [c|f] [forecast-days 0-3]
#   weather-fetch.sh --probe "<city>"     → resolve only, print one JSON line, write nothing
#
# Source: wttr.in (the city name is sent to that external service; no geolocation). Only writes on a
# successful fetch — a transient network failure leaves the last good weather.json in place instead
# of blanking the widget. Read by lock/LockContent.qml via a FileView, exactly like colors.json.
#
# --probe backs the editor's "is this place recognised?" feedback (Settings → Lockscreen → Build
# your own → Weather): it prints {"ok":…,"name":…} and never touches weather.json, so typing in the
# field cannot clobber the live widget.
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

probe=0
if [[ "${1:-}" == "--probe" ]]; then probe=1; shift; fi

city="${1:-}"
unit="${2:-c}"
days="${3:-0}"
out="$VELUMERON_USER_DIR/quickshell/weather.json"

# No city configured → nothing to fetch (the widget shows a "set a city" hint on its own).
if [[ -z "$city" ]]; then
    [[ $probe -eq 1 ]] && echo '{"ok":false}'
    exit 0
fi

# Keep the body AND the HTTP status: the editor must be able to say "unknown place" instead of
# blaming the network. wttr.in is not consistent about it — an unresolvable place comes back as
# 500 with the body "location not found" (older builds: 404, or "Unknown location; please try …"),
# so both signals are checked. (No -f, or curl would swallow body and status alike.)
resp=$(curl -sS --max-time 10 -w $'\n%{http_code}' "https://wttr.in/${city}?format=j1" 2>/dev/null) || resp=""
status="${resp##*$'\n'}"
raw="${resp%$'\n'*}"
if [[ "$status" != "200" || -z "$raw" ]]; then
    if [[ $probe -eq 1 ]]; then
        if [[ "$status" == "404" || "$raw" == *"not found"* || "$raw" == *"Unknown location"* ]]; then
            echo '{"ok":false,"error":"notfound"}'
        else
            echo '{"ok":false,"error":"unreachable"}'
        fi
    fi
    exit 0
fi

[[ $probe -eq 0 ]] && mkdir -p "$(dirname "$out")"

CITY="$city" UNIT="$unit" DAYS="$days" OUT="$out" PROBE="$probe" python3 - "$raw" <<'PY' || exit 0
import json, os, sys, tempfile

probe = os.environ.get("PROBE") == "1"

try:
    d = json.loads(sys.argv[1])
    cur = d["current_condition"][0]
except Exception:
    if probe:
        print(json.dumps({"ok": False}))
        sys.exit(0)
    sys.exit(1)

# The place wttr.in actually resolved the input to — the probe reports it back so the user sees
# WHICH place matched ("Berlin" → "Berlin, Germany"), not just a tick.
def area_name(doc):
    try:
        a = doc["nearest_area"][0]
        def first(k):
            v = a.get(k) or []
            return (v[0].get("value") or "").strip() if v else ""
        parts = [p for p in (first("areaName"), first("region"), first("country")) if p]
        seen, uniq = set(), []          # region often repeats the city — drop the duplicate
        for p in parts:
            if p.lower() not in seen:
                seen.add(p.lower()); uniq.append(p)
        return ", ".join(uniq)
    except Exception:
        return ""

name = area_name(d)

if probe:
    print(json.dumps({"ok": bool(name), "name": name}))
    sys.exit(0)

unit = os.environ.get("UNIT", "c").lower()
temp = cur.get("temp_F") if unit == "f" else cur.get("temp_C")
usym = "°F" if unit == "f" else "°C"
desc = (cur.get("weatherDesc") or [{}])[0].get("value", "").strip()
try:
    code = int(cur.get("weatherCode", 0))
except Exception:
    code = 0

# WWO weather code → a Nerd Font weather glyph (coarse buckets; day/night-agnostic).
def icon_for(c):
    if c == 113:                                   return ""   # clear / sunny
    if c in (116,):                                return ""   # partly cloudy
    if c in (119, 122):                            return ""   # cloudy / overcast
    if c in (143, 248, 260):                       return ""   # fog / mist
    if c in (200, 386, 389, 392, 395):             return ""   # thunder
    if c in (179, 227, 230, 323, 326, 329, 332,
             335, 338, 368, 371, 374, 377):        return ""   # snow / sleet
    if c in (176, 263, 266, 281, 284, 293, 296,
             299, 302, 305, 308, 311, 314, 317,
             320, 350, 353, 356, 359, 362, 365):   return ""   # rain / drizzle
    return ""                                                  # unknown

# Multi-day outlook. wttr.in ships 3 days in j1, so the count is clamped to 0..3 (0 = current only).
# Each day carries the midday condition (the "what will the day be like" glance) plus the day's
# min/max in the same unit as the current temperature. The widget formats the weekday itself from
# `date`, so it follows the shell's locale instead of the API's English.
try:
    want = max(0, min(3, int(os.environ.get("DAYS", "0"))))
except Exception:
    want = 0

days = []
for day in (d.get("weather") or [])[:want]:
    hours = day.get("hourly") or []
    mid = None
    for h in hours:
        if str(h.get("time")) in ("1200", "1300"):
            mid = h
            break
    mid = mid or (hours[len(hours) // 2] if hours else {})
    try:
        dcode = int(mid.get("weatherCode", 0))
    except Exception:
        dcode = 0
    days.append({
        "date": day.get("date", ""),
        "min":  str((day.get("mintempF") if unit == "f" else day.get("mintempC")) or ""),
        "max":  str((day.get("maxtempF") if unit == "f" else day.get("maxtempC")) or ""),
        "icon": icon_for(dcode),
    })

out = {
    "ok": True,
    "temp": str(temp) if temp is not None else "",
    "unit": usym,
    "desc": desc,
    "icon": icon_for(code),
    "city": os.environ.get("CITY", ""),
    "place": name,
    "days": days,
}
path = os.environ["OUT"]
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".weather.")
with os.fdopen(fd, "w") as f:
    json.dump(out, f)
os.replace(tmp, path)   # atomic
PY
