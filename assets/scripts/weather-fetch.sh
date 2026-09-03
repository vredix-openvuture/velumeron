#!/usr/bin/env bash
# Fetch the current weather (+ an optional multi-day outlook) for the lockscreen widget and write a
# compact JSON the shell watches.
#
#   weather-fetch.sh "<query>" [c|f] [forecast-days 0-3] [display-name]
#   weather-fetch.sh --probe "<query>"    → resolve only, print one JSON line, write nothing
#
# <query> is whatever wttr.in should resolve: a place name ("Berlin, Germany") or a "lat,lon" fix.
# The fix is what the city field writes once the user PICKS a suggestion (see city-search.sh) — two
# towns of the same name are one string to wttr.in but two different coordinates. [display-name] is
# then the readable name that goes into weather.json's `city`, so the file never carries coordinates
# where a place belongs; it defaults to <query> when the user typed the name by hand.
#
# Source: wttr.in (the query is sent to that external service; no geolocation). Only writes on a
# successful fetch — a transient network failure leaves the last good weather.json in place instead
# of blanking the widget. Read by lock/LockContent.qml via a FileView, exactly like colors.json.
#
# --probe backs the city field's "is this place recognised?" line (Settings → Lockscreen → Weather,
# Settings → Bar → Weather module): it prints {"ok":…,"name":…} and never touches weather.json, so
# typing in the field cannot clobber the live widget.
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

probe=0
if [[ "${1:-}" == "--probe" ]]; then probe=1; shift; fi

city="${1:-}"
unit="${2:-c}"
days="${3:-0}"
# The readable name for weather.json. Defaults to the query, EXCEPT when the query is a coordinate
# pair — the file would then carry "50.32,10.21" where a place belongs, and every reader that falls
# back from `place` to `city` would print it.
name="${4:-}"
exact=false
if [[ "$city" =~ ^-?[0-9.]+,-?[0-9.]+$ ]]; then exact=true; else name="${name:-$city}"; fi
out="$VELUMERON_USER_DIR/quickshell/weather.json"

# No city configured → nothing to fetch (the widget shows a "set a city" hint on its own).
if [[ -z "$city" ]]; then
    [[ $probe -eq 1 ]] && echo '{"ok":false}'
    exit 0
fi

# Percent-encode the query before it becomes a path segment: any two-word place ("New York",
# "Bad Neustadt an der Saale, Germany") carries a space, and curl cannot send a raw space in a URL
# at all — it fails the request outright, which reads as "no network" rather than "bad input".
query=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=","))' "$city")

# Keep the body AND the HTTP status: the editor must be able to say "unknown place" instead of
# blaming the network. wttr.in is not consistent about it — an unresolvable place comes back as
# 500 with the body "location not found" (older builds: 404, or "Unknown location; please try …"),
# so both signals are checked. (No -f, or curl would swallow body and status alike.)
# An empty query would become "https://wttr.in/?format=j1", which the service answers by locating
# the CALLER'S IP - the one thing the header above promises never happens. It can only come from the
# encoder failing, so it is a guard, not a case.
if [[ -z "$query" ]]; then
    [[ $probe -eq 1 ]] && echo '{"ok":false,"error":"unreachable"}'
    exit 0
fi

resp=$(curl -sS --max-time 10 -w $'\n%{http_code}' "https://wttr.in/${query}?format=j1" 2>/dev/null) || resp=""
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

CITY="$name" EXACT="$exact" UNIT="$unit" DAYS="$days" OUT="$out" PROBE="$probe" python3 - "$raw" <<'PY' || exit 0
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

# WWO weather code -> the condition the shell draws. A KEY, not a glyph: the shell paints its own
# sun, clouds and rain (common/WeatherIcon.qml) so the current sky can move, and a private-use font
# character in a shell script is a thing that silently turns into an empty string the first time
# some tool rewrites the file - which is exactly what had happened to the glyphs that used to be
# here. Coarse buckets, day/night-agnostic; the shell picks sun or moon from sunrise/sunset below.
def cond_for(c):
    if c == 113:                                   return "clear"
    if c == 116:                                   return "partly"
    if c in (119, 122):                            return "cloudy"
    if c in (143, 248, 260):                       return "fog"
    if c in (200, 386, 389, 392, 395):             return "thunder"
    if c in (179, 227, 230, 323, 326, 329, 332,
             335, 338, 368, 371, 374, 377):        return "snow"
    if c in (176, 263, 266, 281, 284, 293, 296,
             299, 302, 305, 308, 311, 314, 317,
             320, 350, 353, 356, 359, 362, 365):   return "rain"
    return "cloudy"                                                 # unknown reads as overcast

# Sunrise and sunset for today, in UTC, so the shell can decide sun-or-moon from the clock at the
# moment the panel is opened rather than from the moment of the fetch - a reading half a day old
# must not still be drawing daylight.
#
# wttr.in reports both in the LOCATION'S local time and ships no timezone, so the offset is taken
# from the longitude: 15 degrees is one hour. That is standard time, so a place on summer time comes
# out an hour off - which moves the switch by an hour inside dusk, not into the middle of the night.
# When the guess lands on this machine's own standard offset, the machine's real offset is used
# instead, so the ordinary case (the city you live in) is exact.
import time

def clock24(value):
    text = (value or "").strip().upper()
    try:
        hhmm, meridiem = text.split(" ")
        hour, minute = (int(x) for x in hhmm.split(":"))
    except Exception:
        return None
    if meridiem == "PM" and hour != 12: hour += 12
    if meridiem == "AM" and hour == 12: hour = 0
    return hour * 60 + minute

def utc_offset_hours(doc):
    machine_std = -time.timezone // 3600
    machine_now = (-time.altzone if (time.daylight and time.localtime().tm_isdst)
                   else -time.timezone) // 3600
    # nearest_area carries longitude as a bare string, while every other field there is a
    # [{"value": ...}] list. Both shapes are accepted rather than trusted.
    raw = (doc.get("nearest_area") or [{}])[0].get("longitude")
    if isinstance(raw, list):
        raw = (raw[0] or {}).get("value") if raw else None
    try:
        lon = float(raw)
    except (TypeError, ValueError):
        return machine_now
    guess = int(round(lon / 15.0))
    return machine_now if guess == machine_std else guess

def to_utc(minutes, offset):
    if minutes is None:
        return ""
    total = (minutes - offset * 60) % 1440
    return "%02d:%02d" % (total // 60, total % 60)

try:
    astro   = ((d.get("weather") or [{}])[0].get("astronomy") or [{}])[0]
    offset  = utc_offset_hours(d)
    sunrise = to_utc(clock24(astro.get("sunrise")), offset)
    sunset  = to_utc(clock24(astro.get("sunset")),  offset)
except Exception:
    sunrise = sunset = ""

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
        "cond": cond_for(dcode),
    })

out = {
    "ok": True,
    "temp": str(temp) if temp is not None else "",
    "unit": usym,
    "desc": desc,
    "cond": cond_for(code),
    "city": os.environ.get("CITY", ""),
    "place": name,
    # Whether the query was a coordinate fix rather than a name. It decides which place the shell
    # NAMES: with a fix, the user picked a town and that is the answer, even though wttr.in reports
    # the nearest station it has - asking for Teisnach and being told "Oberberging" reads as a bug.
    "exact": os.environ.get("EXACT") == "true",
    "sunrise_utc": sunrise,
    "sunset_utc": sunset,
    "days": days,
}
path = os.environ["OUT"]
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".weather.")
with os.fdopen(fd, "w") as f:
    json.dump(out, f)
os.replace(tmp, path)   # atomic
PY
