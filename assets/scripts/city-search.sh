#!/usr/bin/env bash
# Name a half-typed place back to the user, for the city fields in Settings (Lockscreen -> Weather
# and Bar -> Weather module).
#
#   city-search.sh "<query>" [limit]   -> one JSON line on stdout, nothing written to disk
#
# Source: Open-Meteo's geocoding API (open-meteo.com/en/docs/geocoding-api) - free, no key, no
# account. Only the query string leaves the machine; nothing about the machine itself does. The
# weather ITSELF still comes from wttr.in (weather-fetch.sh); this endpoint only names places and
# hands back their coordinates, which is what makes a pick unambiguous: the two German towns called
# Neustadt are one string to wttr.in but two different fixes here.
#
# Output shape (a name that starts with the query first, biggest place first within that):
#   {"ok":true,"results":[{"name":"Berlin","detail":"Land Berlin, Deutschland",
#                          "value":"Berlin, Deutschland","coords":"52.5244,13.4105"}]}
#   - value  = what goes into the text field AND onto disk: the place in the user's language, but
#              the country as its ISO code, so the stored string stays the same whatever locale it
#              was picked under. wttr.in resolves that form on its own, which is what makes it a
#              usable fallback when there are no coordinates.
#   - coords = the exact fix that is fetched when the user PICKED this entry instead of typing
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

q="${1:-}"
limit="${2:-6}"

# Two characters is where the API starts returning anything useful, and it keeps a keystroke like
# "B" from firing a request that can only come back as noise.
if [[ "${#q}" -lt 2 ]]; then
    echo '{"ok":true,"results":[]}'
    exit 0
fi

# Place names in the user's language when the API speaks it, English otherwise. The labels are data
# from the service, not shell strings - the surrounding UI stays English either way.
lang="${LANG%%_*}"
case "$lang" in de|en|fr|es|it|pt|ru|tr|hi|nl|pl|sv|cs|ja|zh|ko) ;; *) lang=en ;; esac

quote() { python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
search_url() {
    printf 'https://geocoding-api.open-meteo.com/v1/search?name=%s&count=%s&language=%s&format=json' \
           "$(quote "$1")" "$2" "$lang"
}

# Two queries, not one. Open-Meteo drops the prefix match the moment the query ends on a complete
# word: "New Yor" returns New York City first, "New York" does not return it at all. So a query of
# four characters or more is asked a second time one character shorter and the answers are merged.
# The two requests run in parallel, so the second one costs no extra wait.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sS --max-time 8 "$(search_url "$q" 10)" > "$work/full" 2>/dev/null &
if [[ "${#q}" -ge 4 ]]; then
    curl -sS --max-time 8 "$(search_url "${q:0:${#q}-1}" 10)" > "$work/short" 2>/dev/null &
fi
wait

QUERY="$q" LIMIT="$limit" python3 - "$(cat "$work/full" 2>/dev/null)" "$(cat "$work/short" 2>/dev/null)" <<'PY'
import json, os, sys

query = os.environ.get("QUERY", "").strip().lower()
try:
    limit = max(1, int(os.environ.get("LIMIT", "6")))
except ValueError:
    limit = 6

# The endpoint answers a bad request with HTTP 200 and {"error":true,"reason":...}, and a query
# that simply matched nothing with a document that has no "results" key at all. Both would read as
# "no such place" if only the result list were counted, so a payload that is neither a reachable
# answer nor a parseable document makes the whole lookup fail loudly instead.
places, answered = [], False
for payload in sys.argv[1:]:
    if not payload.strip():
        continue
    try:
        doc = json.loads(payload)
    except Exception:
        continue
    if doc.get("error"):
        continue
    answered = True
    places.extend(doc.get("results") or [])

if not answered:
    print(json.dumps({"ok": False, "error": "unreachable", "results": []}))
    sys.exit(0)

out, seen = [], set()
for place in places:
    name    = (place.get("name") or "").strip()
    country = (place.get("country") or "").strip()
    code    = (place.get("country_code") or "").strip().upper()
    lat, lon = place.get("latitude"), place.get("longitude")
    if not name or lat is None or lon is None:
        continue
    coords = "%s,%s" % (round(float(lat), 4), round(float(lon), 4))
    if coords in seen:                  # the same place comes back from both queries
        continue
    seen.add(coords)
    # admin1/admin2 tell two same-named towns apart; admin1 often just repeats the city (city
    # states), so a part that echoes the name is dropped rather than shown twice.
    parts, echoed = [], {name.lower()}
    for key in ("admin1", "admin2"):
        part = (place.get(key) or "").strip()
        if part and part.lower() not in echoed:
            echoed.add(part.lower()); parts.append(part)
    if country and country.lower() not in echoed:
        parts.append(country)
    low = name.lower()
    out.append({
        # What the typist most likely meant: a name that starts with what they wrote, biggest place
        # first. Population has to outrank an exact match, or "Ber" buries Berlin under four
        # villages actually called Ber, and "New York" buries New York City under a Lincolnshire
        # hamlet - both measured against this endpoint.
        "_rank":  (0 if low.startswith(query) else 1, -(place.get("population") or 0)),
        "name":   name,
        "detail": ", ".join(parts),
        "value":  "%s, %s" % (name, code) if code else name,
        "coords": coords,
    })

out.sort(key=lambda p: p["_rank"])
for p in out:
    del p["_rank"]

print(json.dumps({"ok": True, "results": out[:limit]}))
PY
