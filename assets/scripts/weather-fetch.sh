#!/usr/bin/env bash
# Fetch the current weather for the lockscreen widget and write a compact JSON the shell watches.
#
#   weather-fetch.sh "<city>" [c|f]
#
# Source: wttr.in (the city name is sent to that external service; no geolocation). Only writes on a
# successful fetch — a transient network failure leaves the last good weather.json in place instead
# of blanking the widget. Read by lock/LockContent.qml via a FileView, exactly like colors.json.
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

city="${1:-}"
unit="${2:-c}"
out="$VELUMERON_USER_DIR/quickshell/weather.json"

# No city configured → nothing to fetch (the widget shows a "set a city" hint on its own).
[[ -z "$city" ]] && exit 0

raw=$(curl -fsS --max-time 10 "https://wttr.in/${city}?format=j1" 2>/dev/null) || exit 0
[[ -z "$raw" ]] && exit 0

mkdir -p "$(dirname "$out")"
CITY="$city" UNIT="$unit" OUT="$out" python3 - "$raw" <<'PY' || exit 0
import json, os, sys, tempfile

try:
    d = json.loads(sys.argv[1])
    cur = d["current_condition"][0]
except Exception:
    sys.exit(1)

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
    if c == 113:                                   return ""   # clear / sunny
    if c in (116,):                                return ""   # partly cloudy
    if c in (119, 122):                            return ""   # cloudy / overcast
    if c in (143, 248, 260):                       return ""   # fog / mist
    if c in (200, 386, 389, 392, 395):             return ""   # thunder
    if c in (179, 227, 230, 323, 326, 329, 332,
             335, 338, 368, 371, 374, 377):        return ""   # snow / sleet
    if c in (176, 263, 266, 281, 284, 293, 296,
             299, 302, 305, 308, 311, 314, 317,
             320, 350, 353, 356, 359, 362, 365):   return ""   # rain / drizzle
    return ""                                                  # unknown

out = {
    "ok": True,
    "temp": str(temp) if temp is not None else "",
    "unit": usym,
    "desc": desc,
    "icon": icon_for(code),
    "city": os.environ.get("CITY", ""),
}
path = os.environ["OUT"]
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".weather.")
with os.fdopen(fd, "w") as f:
    json.dump(out, f)
os.replace(tmp, path)   # atomic
PY
