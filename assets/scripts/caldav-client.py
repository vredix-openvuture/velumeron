#!/usr/bin/env python3
"""CalDAV client for the quickshell calendar menu (stdlib only).

Speaks plain CalDAV (RFC 4791), so Nextcloud Calendar, Nextcloud Tasks and Vikunja
all work with the same code path: VEVENT calendars feed the month view, VTODO
calendars feed the task list. Every command prints the full JSON cache on stdout
(single line) so the QML service has one parse path for load / sync / mutations.

Commands:
  load                                  print the cache without touching the network
  sync                                  refresh all accounts, write + print the cache
  add-account                           creds via env CD_NAME/CD_URL/CD_USER/CD_PASS
  remove-account <name>
  add-todo <calId> <summary> [dueYMD]
  toggle-todo <calId> <href> <0|1>
  add-event <calId> <summary> <YYYY-MM-DD> [HH:MM] [durationMin] [endYMD]
             (no HH:MM → all-day; endYMD makes it span start..end inclusive)
  add-event-full <calId> <jsonEvent>        {summary,ymd,hm,durMin,location,notes,categories,
                                             attendees,icon,imageData,imageType}
  update-event <calId> <href> <jsonPatch>   any subset of the same fields
      Either form takes "@<path>" instead of the JSON itself, which is required
      once an event carries a picture: imageData is base64 and argv caps a
      single entry at 128KB.
  delete-item <calId> <href>

calId = "<account name>|<calendar href>". Accounts live in
$VELUMERON_USER_DIR/gui/caldav-accounts.json (chmod 600 — use app passwords);
the cache in ~/.cache/velumeron/caldav-cache.json.
"""

import base64
import hashlib
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone

try:
    from zoneinfo import ZoneInfo
except ImportError:                                    # pragma: no cover
    ZoneInfo = None


def _local_zone():
    """A real IANA zone (so DST shifts don't skew recurring events across the
    change), falling back to the fixed current offset."""
    if ZoneInfo is not None:
        try:
            tzname = os.environ.get("TZ") or \
                os.path.realpath("/etc/localtime").split("/zoneinfo/", 1)[1]
            return ZoneInfo(tzname)
        except Exception:
            pass
    return datetime.now().astimezone().tzinfo


LOCAL_TZ = _local_zone()

NS = {
    "d":    "DAV:",
    "c":    "urn:ietf:params:xml:ns:caldav",
    "ical": "http://apple.com/ns/ical/",
    "cs":   "http://calendarserver.org/ns/",
}

# Occurrence window for the month view: enough past for context, a year+ ahead.
WIN_PAST_DAYS   = 60
WIN_FUTURE_DAYS = 400
MAX_OCCURRENCES = 400          # per recurring event
COMPLETED_KEEP_DAYS = 30       # drop completed todos older than this


def user_dir():
    u = os.environ.get("VELUMERON_USER_DIR")
    if u:
        return u
    xdg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(xdg, "velumeron")


ACCOUNTS_PATH = os.path.join(user_dir(), "gui", "caldav-accounts.json")
CACHE_PATH = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
    "velumeron", "caldav-cache.json")
# Event pictures arrive inside the event as an RFC 5545 ATTACH. They are written
# out here and only the PATH goes into the JSON cache: 200 events with a picture
# would otherwise add ~20MB of base64 that gets re-parsed on every start.
IMAGE_CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
    "velumeron", "event-images")


# ── Small file helpers ────────────────────────────────────────────────────────

def load_accounts():
    try:
        with open(ACCOUNTS_PATH) as f:
            return json.load(f).get("accounts", [])
    except (OSError, ValueError):
        return []


def save_accounts(accounts):
    os.makedirs(os.path.dirname(ACCOUNTS_PATH), exist_ok=True)
    with open(ACCOUNTS_PATH, "w") as f:
        json.dump({"accounts": accounts}, f, indent=2)
    os.chmod(ACCOUNTS_PATH, 0o600)


def load_cache():
    try:
        with open(CACHE_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"syncedAt": 0, "accounts": [], "calendars": [], "events": [], "todos": []}


def save_cache(cache):
    os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
    tmp = CACHE_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cache, f)
    os.replace(tmp, CACHE_PATH)


def emit(cache):
    print(json.dumps(cache, separators=(",", ":")))


# ── HTTP (urllib with manual redirects so PROPFIND/REPORT survive 301s) ──────

def http(method, url, account, body=None, headers=None, depth=None):
    hdrs = {
        "User-Agent":    "velumeron-caldav/1.0",
        "Authorization": "Basic " + base64.b64encode(
            f"{account['username']}:{account['password']}".encode()).decode(),
    }
    if body is not None:
        hdrs["Content-Type"] = "application/xml; charset=utf-8" \
            if body.lstrip().startswith("<") else "text/calendar; charset=utf-8"
    if depth is not None:
        hdrs["Depth"] = str(depth)
    if headers:
        hdrs.update(headers)

    data = body.encode() if isinstance(body, str) else body
    ctx = ssl.create_default_context()
    for _ in range(5):
        req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
        try:
            resp = urllib.request.urlopen(req, timeout=20, context=ctx)
            return resp.status, dict(resp.headers), resp.read()
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 307, 308) and e.headers.get("Location"):
                url = urllib.parse.urljoin(url, e.headers["Location"])
                continue
            return e.code, dict(e.headers), e.read()
    raise RuntimeError("too many redirects")


def full_url(base, href):
    # Resolve href against base, then percent-encode the path. Servers may hand
    # back hrefs with raw characters that urllib.request rejects — Nextcloud, for
    # one, returns principal/calendar paths with a LITERAL SPACE when the user id
    # has one (e.g. .../users/Adrian Fredl/). `%` is in `safe` so already-encoded
    # hrefs (%20) are not double-encoded.
    parts = urllib.parse.urlsplit(urllib.parse.urljoin(base, href))
    path = urllib.parse.quote(parts.path, safe="/%:@&=+$,;~()!*'")
    return urllib.parse.urlunsplit((parts.scheme, parts.netloc, path, parts.query, parts.fragment))


# ── CalDAV discovery ──────────────────────────────────────────────────────────

def _propfind(url, account, props, depth):
    body = ('<?xml version="1.0" encoding="utf-8"?>'
            '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"'
            ' xmlns:ical="http://apple.com/ns/ical/" xmlns:cs="http://calendarserver.org/ns/">'
            f'<d:prop>{props}</d:prop></d:propfind>')
    status, _, data = http("PROPFIND", url, account, body, depth=depth)
    if status not in (207,):
        raise RuntimeError(f"PROPFIND {url} → HTTP {status}")
    return ET.fromstring(data)


def _href_prop(tree, path):
    el = tree.find(f".//{path}/d:href", NS)
    return el.text.strip() if el is not None and el.text else None


def discover_calendars(account):
    """URL → list of calendar dicts. Tolerates any entry point: server root,
    /.well-known/caldav, the DAV root, the calendar home, or a single calendar."""
    url = account["url"].strip()
    if not re.match(r"^https?://", url):
        url = "https://" + url
    if not url.endswith("/"):
        url += "/"

    home = None
    try:
        tree = _propfind(url, account, "<d:current-user-principal/>", 0)
        principal = _href_prop(tree, "d:current-user-principal")
        if principal:
            tree = _propfind(full_url(url, principal), account,
                             "<c:calendar-home-set/>", 0)
            h = _href_prop(tree, "c:calendar-home-set")
            if h:
                home = full_url(url, h)
    except Exception:
        pass                            # fall through to direct listing
    listing_url = home or url

    props = ("<d:resourcetype/><d:displayname/><ical:calendar-color/>"
             "<c:supported-calendar-component-set/><d:current-user-privilege-set/>")
    tree = _propfind(listing_url, account, props, 1)

    cals = []
    for resp in tree.findall("d:response", NS):
        href = resp.findtext("d:href", default="", namespaces=NS).strip()
        rtype = resp.find(".//d:resourcetype", NS)
        if rtype is None or rtype.find("c:calendar", NS) is None:
            continue
        name = resp.findtext(".//d:displayname", default="", namespaces=NS) or \
            urllib.parse.unquote(href.rstrip("/").rsplit("/", 1)[-1])
        color = (resp.findtext(".//ical:calendar-color", default="", namespaces=NS) or "").strip()
        if len(color) == 9 and color.startswith("#"):
            color = color[:7]           # strip the alpha nibble Apple-style colors carry
        comps = [c.get("name") for c in
                 resp.findall(".//c:supported-calendar-component-set/c:comp", NS)]
        if not comps:
            comps = ["VEVENT", "VTODO"]
        priv = resp.find(".//d:current-user-privilege-set", NS)
        writable = True
        if priv is not None and len(priv):
            writable = priv.find(".//d:write", NS) is not None or \
                priv.find(".//d:write-content", NS) is not None
        cals.append({
            "id":       account["name"] + "|" + href,
            "account":  account["name"],
            "href":     href,
            "url":      full_url(listing_url, href),
            "name":     name,
            "color":    color,
            "vevent":   "VEVENT" in comps,
            "vtodo":    "VTODO" in comps,
            "writable": writable,
        })
    if not cals:
        raise RuntimeError("no calendars found at " + listing_url)
    return cals


# ── ICS parsing ───────────────────────────────────────────────────────────────

def _unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text.replace("\r\n", "\n"))


def _unescape(v):
    return v.replace("\\n", "\n").replace("\\N", "\n") \
            .replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")


def _parse_line(line):
    """NAME;PARAM=a;PARAM="b:c":value → (name, {param: value}, value)"""
    i, in_q = 0, False
    while i < len(line):
        ch = line[i]
        if ch == '"':
            in_q = not in_q
        elif ch == ":" and not in_q:
            break
        i += 1
    head, value = line[:i], line[i + 1:]
    parts = []
    j, in_q, cur = 0, False, ""
    for ch in head:
        if ch == '"':
            in_q = not in_q
        elif ch == ";" and not in_q:
            parts.append(cur)
            cur = ""
            continue
        cur += ch
    parts.append(cur)
    name = parts[0].upper()
    params = {}
    for p in parts[1:]:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.upper()] = v.strip('"')
    return name, params, value


def parse_components(ics_text, kind):
    """Extract all components of `kind` ("VEVENT"/"VTODO") as prop dicts:
    { NAME: [(params, value), ...] }."""
    out, cur, depth = [], None, 0
    for line in _unfold(ics_text).split("\n"):
        line = line.strip("\r")
        if not line:
            continue
        if line.upper().startswith("BEGIN:"):
            what = line[6:].strip().upper()
            if what == kind and cur is None:
                cur = {}
            elif cur is not None:
                depth += 1
            continue
        if line.upper().startswith("END:"):
            what = line[4:].strip().upper()
            if cur is not None:
                if depth > 0:
                    depth -= 1
                elif what == kind:
                    out.append(cur)
                    cur = None
            continue
        if cur is not None and depth == 0:
            name, params, value = _parse_line(line)
            cur.setdefault(name, []).append((params, value))
    return out


def _first(comp, name):
    vs = comp.get(name)
    return vs[0] if vs else (None, None)


def parse_dt(params, value, default_tz=None):
    """ICS date / date-time → (aware datetime, all_day). Unknown TZIDs fall back
    to the local zone (good enough for a personal calendar)."""
    params = params or {}
    value = value.strip()
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        d = datetime.strptime(value, "%Y%m%d")
        return d.replace(tzinfo=LOCAL_TZ), True
    utc = value.endswith("Z")
    v = value.rstrip("Z")
    dt = datetime.strptime(v, "%Y%m%dT%H%M%S")
    if utc:
        return dt.replace(tzinfo=timezone.utc).astimezone(LOCAL_TZ), False
    tzid = params.get("TZID")
    tz = default_tz or LOCAL_TZ
    if tzid and ZoneInfo is not None:
        try:
            tz = ZoneInfo(tzid)
        except Exception:
            pass
    return dt.replace(tzinfo=tz).astimezone(LOCAL_TZ), False


def parse_duration(value):
    m = re.fullmatch(
        r"([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?",
        value.strip())
    if not m:
        return timedelta()
    sign = -1 if m.group(1) == "-" else 1
    w, d, h, mi, s = (int(x) if x else 0 for x in m.groups()[1:])
    return sign * timedelta(weeks=w, days=d, hours=h, minutes=mi, seconds=s)


# ── Recurrence expansion (the common personal-calendar subset of RFC 5545) ───

_WEEKDAYS = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}


def _parse_rrule(value):
    rule = {}
    for part in value.split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            rule[k.upper()] = v
    return rule


def _nth_weekday(year, month, weekday, ordinal):
    """ordinal-th `weekday` of a month (negative = from the end), or None."""
    if ordinal > 0:
        d = date(year, month, 1)
        off = (weekday - d.weekday()) % 7
        d = d + timedelta(days=off + (ordinal - 1) * 7)
        return d if d.month == month else None
    last = date(year + (month == 12), month % 12 + 1, 1) - timedelta(days=1)
    off = (last.weekday() - weekday) % 7
    d = last - timedelta(days=off + (-ordinal - 1) * 7)
    return d if d.month == month else None


def expand_rrule(dtstart, rule, win_start, win_end):
    """Occurrence starts for the supported RRULE subset, DTSTART included.
    Unsupported patterns (BYSETPOS etc.) → just the master occurrence."""
    freq = rule.get("FREQ", "").upper()
    interval = max(1, int(rule.get("INTERVAL", 1) or 1))
    count = int(rule["COUNT"]) if rule.get("COUNT") else None
    until = None
    if rule.get("UNTIL"):
        until, _ = parse_dt({}, rule["UNTIL"])
    if "BYSETPOS" in rule or freq not in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY"):
        return [dtstart]

    occurrences, n_checked = [], 0

    def push(dt):
        occurrences.append(dt)
        return (count is not None and len(occurrences) >= count) or \
               (until is not None and dt > until) or \
               dt > win_end or len(occurrences) >= MAX_OCCURRENCES + 200

    if freq == "DAILY":
        dt = dtstart
        while not push(dt):
            dt = dt + timedelta(days=interval)

    elif freq == "WEEKLY":
        bydays = [_WEEKDAYS[d] for d in rule.get("BYDAY", "").split(",")
                  if d in _WEEKDAYS] or [dtstart.weekday()]
        week0 = dtstart - timedelta(days=dtstart.weekday())   # WKST=MO
        w = 0
        done = False
        while not done:
            base = week0 + timedelta(weeks=w * interval)
            for wd in sorted(bydays):
                dt = base + timedelta(days=wd)
                if dt < dtstart:
                    continue
                if push(dt):
                    done = True
                    break
            w += 1
            if w > 6000:
                break

    elif freq == "MONTHLY":
        byday = rule.get("BYDAY", "")
        m_ord = re.fullmatch(r"(-?\d+)([A-Z]{2})", byday) if byday else None
        bymonthday = int(rule["BYMONTHDAY"]) if rule.get("BYMONTHDAY") else \
            (None if m_ord else dtstart.day)
        y, mo = dtstart.year, dtstart.month
        done = False
        while not done and n_checked < 6000:
            n_checked += 1
            d = None
            if m_ord:
                nd = _nth_weekday(y, mo, _WEEKDAYS[m_ord.group(2)], int(m_ord.group(1)))
                if nd:
                    d = dtstart.replace(year=nd.year, month=nd.month, day=nd.day)
            else:
                try:
                    d = dtstart.replace(year=y, month=mo, day=bymonthday)
                except ValueError:
                    d = None                     # e.g. Feb 31st — skip the month
            if d is not None and d >= dtstart and push(d):
                done = True
            mo += interval
            y, mo = y + (mo - 1) // 12, (mo - 1) % 12 + 1

    elif freq == "YEARLY":
        mo = int(rule["BYMONTH"]) if rule.get("BYMONTH") else dtstart.month
        day = int(rule["BYMONTHDAY"]) if rule.get("BYMONTHDAY") else dtstart.day
        y = dtstart.year
        done = False
        while not done and n_checked < 1200:
            n_checked += 1
            try:
                d = dtstart.replace(year=y, month=mo, day=day)
                if d >= dtstart and push(d):
                    done = True
            except ValueError:
                pass                             # Feb 29 on non-leap years
            y += interval

    if count is not None:
        occurrences = occurrences[:count]
    if until is not None:
        occurrences = [o for o in occurrences if o <= until]
    return [o for o in occurrences if o >= win_start and o <= win_end][:MAX_OCCURRENCES]


# ── Calendar REPORT + JSON shaping ────────────────────────────────────────────

def _report(cal, account, comp, time_range=None):
    tr = f'<c:time-range start="{time_range[0]}" end="{time_range[1]}"/>' if time_range else ""
    body = ('<?xml version="1.0" encoding="utf-8"?>'
            '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
            '<d:prop><d:getetag/><c:calendar-data/></d:prop>'
            '<c:filter><c:comp-filter name="VCALENDAR">'
            f'<c:comp-filter name="{comp}">{tr}</c:comp-filter>'
            '</c:comp-filter></c:filter></c:calendar-query>')
    status, _, data = http("REPORT", cal["url"], account, body, depth=1)
    if status != 207:
        raise RuntimeError(f"REPORT {comp} on {cal['name']} → HTTP {status}")
    items = []
    for resp in ET.fromstring(data).findall("d:response", NS):
        href = resp.findtext("d:href", default="", namespaces=NS).strip()
        etag = (resp.findtext(".//d:getetag", default="", namespaces=NS) or "").strip()
        ics = resp.findtext(".//c:calendar-data", default="", namespaces=NS)
        if ics:
            items.append((href, etag, ics))
    return items


def _text(comp, name):
    _, v = _first(comp, name)
    return _unescape(v) if v else ""


def _categories(comp):
    out = []
    for _p, v in comp.get("CATEGORIES", []):
        out += [c.strip() for c in _unescape(v or "").split(",") if c.strip()]
    return out


def _attendees(comp):
    """ATTENDEE lines → [{name, email, phone}]. Value is a CAL-ADDRESS
    (mailto:/tel:); CN param holds the name, X-PHONE a phone when there's no tel:."""
    out = []
    for params, v in comp.get("ATTENDEE", []):
        val = (v or "").strip()
        email, phone = "", params.get("X-PHONE", "")
        if val.lower().startswith("mailto:"):
            email = val[7:]
        elif val.lower().startswith("tel:"):
            phone = phone or val[4:]
        out.append({"name": params.get("CN", ""), "email": email, "phone": phone})
    return out


_IMG_EXT = {"image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png",
            "image/gif": ".gif", "image/webp": ".webp"}
# base64 payload → written path. A recurring event is shaped once per occurrence,
# so without this the same picture would be decoded and hashed up to 400 times.
_ATTACH_CACHE = {}


def _attached_image(comp):
    """First inline image ATTACH → its path in IMAGE_CACHE ("" if there is none).

    Content-addressed, so the same picture on ten events is one file and the
    path stays stable across syncs (an Image source that keeps changing
    re-decodes and flickers)."""
    for params, v in comp.get("ATTACH", []):
        fmt = (params.get("FMTTYPE") or "").lower()
        if params.get("ENCODING", "").upper() != "BASE64" or not fmt.startswith("image/"):
            continue                            # a URI attachment or a non-image
        b64 = (v or "").strip()
        if not b64:
            continue
        if b64 in _ATTACH_CACHE:
            return _ATTACH_CACHE[b64]
        try:
            data = base64.b64decode(b64)
        except Exception:                                       # noqa: BLE001
            continue
        if not data:
            continue
        path = os.path.join(IMAGE_CACHE,
                            hashlib.sha1(data).hexdigest()[:16] + _IMG_EXT.get(fmt, ".img"))
        if not os.path.exists(path):
            os.makedirs(IMAGE_CACHE, exist_ok=True)
            tmp = path + ".tmp"
            with open(tmp, "wb") as f:
                f.write(data)
            os.replace(tmp, path)
        _ATTACH_CACHE[b64] = path
        return path
    return ""


def _event_extra(src):
    """The rich fields shared by every shaped event."""
    # X-VELORGANIZE-IMAGE is the old form: an absolute path, meaningless on any
    # other machine. Still read as a fallback until every event is migrated.
    return {"notes": _text(src, "DESCRIPTION"), "location": _text(src, "LOCATION"),
            "categories": _categories(src), "attendees": _attendees(src),
            "icon": _text(src, "X-VELORGANIZE-ICON"),
            "image": _attached_image(src) or _text(src, "X-VELORGANIZE-IMAGE")}


def shape_events(cal, items, win_start, win_end):
    events = []
    for href, etag, ics in items:
        comps = parse_components(ics, "VEVENT")
        masters = [c for c in comps if "RECURRENCE-ID" not in c]
        overrides = {}
        for c in comps:
            if "RECURRENCE-ID" in c:
                p, v = _first(c, "RECURRENCE-ID")
                rid, _ = parse_dt(p, v)
                overrides[int(rid.timestamp())] = c

        for m in masters:
            p, v = _first(m, "DTSTART")
            if not v:
                continue
            dtstart, all_day = parse_dt(p, v)
            pe, ve = _first(m, "DTEND")
            if ve:
                dtend, _ = parse_dt(pe, ve)
            else:
                pd, vd = _first(m, "DURATION")
                dtend = dtstart + (parse_duration(vd) if vd else
                                   (timedelta(days=1) if all_day else timedelta()))
            duration = dtend - dtstart

            pr, vr = _first(m, "RRULE")
            if vr:
                starts = expand_rrule(dtstart, _parse_rrule(vr), win_start, win_end)
            else:
                starts = [dtstart] if dtstart <= win_end and dtend >= win_start else []

            exdates = set()
            for pex, vex in m.get("EXDATE", []):
                for one in vex.split(","):
                    exd, _ = parse_dt(pex, one)
                    exdates.add(int(exd.timestamp()))

            for s in starts:
                ts = int(s.timestamp())
                if ts in exdates:
                    continue
                src = overrides.pop(ts, m)
                sp, sv = _first(src, "DTSTART")
                if src is not m and sv:
                    s, all_day2 = parse_dt(sp, sv)
                    ep2, ev2 = _first(src, "DTEND")
                    e = parse_dt(ep2, ev2)[0] if ev2 else s + duration
                else:
                    all_day2, e = all_day, s + duration
                if _text(src, "STATUS").upper() == "CANCELLED":
                    continue
                events.append({
                    "cal":      cal["id"],
                    "href":     href,
                    "etag":     etag,
                    "uid":      _text(src, "UID"),
                    "summary":  _text(src, "SUMMARY") or "(untitled)",
                    "allDay":   all_day2,
                    "startMs":  int(s.timestamp() * 1000),
                    "endMs":    int(e.timestamp() * 1000),
                    "recurring": bool(vr),
                    **_event_extra(src),
                })
        # Overrides moved outside the expansion window still count if in range.
        for c in overrides.values():
            sp, sv = _first(c, "DTSTART")
            if not sv:
                continue
            s, ad = parse_dt(sp, sv)
            if s > win_end or s < win_start or _text(c, "STATUS").upper() == "CANCELLED":
                continue
            ep, ev = _first(c, "DTEND")
            e = parse_dt(ep, ev)[0] if ev else s
            events.append({
                "cal": cal["id"], "href": href, "etag": etag, "uid": _text(c, "UID"),
                "summary": _text(c, "SUMMARY") or "(untitled)", "allDay": ad,
                "startMs": int(s.timestamp() * 1000), "endMs": int(e.timestamp() * 1000),
                "recurring": True,
                **_event_extra(c),
            })
    return events


def shape_todos(cal, items):
    todos, cutoff = [], (datetime.now(LOCAL_TZ) - timedelta(days=COMPLETED_KEEP_DAYS))
    for href, etag, ics in items:
        for c in parse_components(ics, "VTODO"):
            completed = _text(c, "STATUS").upper() == "COMPLETED" or \
                (_first(c, "PERCENT-COMPLETE")[1] or "") == "100"
            done_ms = 0
            pc, vc = _first(c, "COMPLETED")
            if vc:
                done_dt, _ = parse_dt(pc, vc)
                done_ms = int(done_dt.timestamp() * 1000)
                if completed and done_dt < cutoff:
                    continue
            due_ms = 0
            pd, vd = _first(c, "DUE")
            due_all_day = False
            if vd:
                due_dt, due_all_day = parse_dt(pd, vd)
                due_ms = int(due_dt.timestamp() * 1000)
            try:
                prio = int(_first(c, "PRIORITY")[1] or 0)
            except ValueError:
                prio = 0
            todos.append({
                "cal":       cal["id"],
                "href":      href,
                "etag":      etag,
                "uid":       _text(c, "UID"),
                "summary":   _text(c, "SUMMARY") or "(untitled)",
                "notes":     _text(c, "DESCRIPTION"),
                "dueMs":     due_ms,
                "dueAllDay": due_all_day,
                "completed": completed,
                "doneMs":    done_ms,
                "priority":  prio,
                "parent":    _text(c, "RELATED-TO"),
            })
    return todos


# ── Sync ──────────────────────────────────────────────────────────────────────

def sync():
    now = datetime.now(LOCAL_TZ)
    win_start = now - timedelta(days=WIN_PAST_DAYS)
    win_end = now + timedelta(days=WIN_FUTURE_DAYS)
    tr = (win_start.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
          win_end.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))

    cache = {"syncedAt": int(now.timestamp() * 1000),
             "accounts": [], "calendars": [], "events": [], "todos": []}

    # Discovery (PROPFIND, one per account) is cheap. The REPORT queries that
    # follow — one or two per calendar — are what actually add up: 34
    # calendars fetched sequentially took ~9s. They're independent reads, so
    # fan them out instead (this used to run after EVERY mutation too, via
    # the emit(sync()) call in main() below, making every add/toggle/delete
    # pay the full ~9s).
    jobs = []       # (entry, cal) — one per calendar, across all accounts
    for account in load_accounts():
        entry = {"name": account["name"], "url": account["url"],
                 "username": account["username"], "ok": True, "error": ""}
        try:
            for cal in discover_calendars(account):
                cache["calendars"].append(cal)
                jobs.append((account, entry, cal))
        except Exception as e:
            entry["ok"] = False
            entry["error"] = str(e)
        cache["accounts"].append(entry)

    def fetch_one(account, entry, cal):
        try:
            events = (shape_events(cal, _report(cal, account, "VEVENT", tr), win_start, win_end)
                      if cal["vevent"] else [])
            todos = shape_todos(cal, _report(cal, account, "VTODO")) if cal["vtodo"] else []
            return events, todos
        except Exception as e:
            entry["ok"] = False
            entry["error"] = f"{cal['name']}: {e}"
            return [], []

    if jobs:
        with ThreadPoolExecutor(max_workers=12) as pool:
            for events, todos in pool.map(lambda j: fetch_one(*j), jobs):
                cache["events"] += events
                cache["todos"] += todos

    cache["events"].sort(key=lambda e: e["startMs"])
    cache["todos"].sort(key=lambda t: (t["completed"],
                                       t["dueMs"] if t["dueMs"] else 2**62,
                                       t["priority"] if t["priority"] else 10))
    save_cache(cache)
    return cache


def find_cal(cache, cal_id):
    for c in cache["calendars"]:
        if c["id"] == cal_id:
            return c
    raise RuntimeError("unknown calendar " + cal_id)


def find_account(name):
    for a in load_accounts():
        if a["name"] == name:
            return a
    raise RuntimeError("unknown account " + name)


# ── Mutations ─────────────────────────────────────────────────────────────────

def _ics_escape(v):
    return v.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def _stamp():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _fold(line):
    """Fold to 75 octets (RFC 5545 3.1). Nothing folded on write before, which
    was survivable for a SUMMARY and is not for a base64 ATTACH — servers are
    entitled to reject an over-long line. The limit counts OCTETS, so a
    multi-byte character must never be split across the break."""
    raw = line.encode()
    if len(raw) <= 75:
        return line
    parts, first = [], True
    while raw:
        cut = 75 if first else 74               # a continuation costs one space
        chunk = raw[:cut]
        # Never cut mid-sequence: back off while the next byte is a UTF-8
        # continuation byte (10xxxxxx).
        while len(chunk) < len(raw) and (raw[len(chunk)] & 0xC0) == 0x80:
            chunk = chunk[:-1]
        parts.append(("" if first else " ") + chunk.decode())
        raw, first = raw[len(chunk):], False
    return "\r\n".join(parts)


def put_new(cal, account, component_lines):
    uid = str(uuid.uuid4())
    ics = "\r\n".join(_fold(l) for l in [
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//velumeron//caldav//EN",
        *component_lines(uid),
        "END:VCALENDAR", ""])
    url = cal["url"].rstrip("/") + "/" + uid + ".ics"
    status, _, body = http("PUT", url, account, ics,
                           headers={"If-None-Match": "*"})
    if status not in (200, 201, 204):
        raise RuntimeError(f"PUT → HTTP {status}: {body[:200].decode(errors='replace')}")


def add_todo(cache, cal_id, summary, due=None):
    cal = find_cal(cache, cal_id)
    account = find_account(cal["account"])

    def lines(uid):
        ls = ["BEGIN:VTODO", f"UID:{uid}", f"DTSTAMP:{_stamp()}", f"CREATED:{_stamp()}",
              f"SUMMARY:{_ics_escape(summary)}", "STATUS:NEEDS-ACTION"]
        if due:
            ls.append("DUE;VALUE=DATE:" + due.replace("-", ""))
        ls.append("END:VTODO")
        return ls
    put_new(cal, account, lines)


def add_event(cache, cal_id, summary, ymd, hm=None, duration_min=60, end_ymd=None, notes=None):
    cal = find_cal(cache, cal_id)
    account = find_account(cal["account"])
    d = datetime.strptime(ymd, "%Y-%m-%d")

    def lines(uid):
        ls = ["BEGIN:VEVENT", f"UID:{uid}", f"DTSTAMP:{_stamp()}",
              f"SUMMARY:{_ics_escape(summary)}"]
        if notes:
            ls.append("DESCRIPTION:" + _ics_escape(notes))
        if hm:
            h, m = hm.split(":")
            start = d.replace(hour=int(h), minute=int(m), tzinfo=LOCAL_TZ)
            end = start + timedelta(minutes=duration_min)
            fmt = "%Y%m%dT%H%M%SZ"
            ls.append("DTSTART:" + start.astimezone(timezone.utc).strftime(fmt))
            ls.append("DTEND:" + end.astimezone(timezone.utc).strftime(fmt))
        else:
            # All-day event; optional end_ymd makes it span multiple days. DTEND;VALUE=DATE is
            # EXCLUSIVE, so a start==end single-day event ends the next day, a range ends end+1.
            last = datetime.strptime(end_ymd, "%Y-%m-%d") if end_ymd else d
            if last < d:
                last = d
            ls.append("DTSTART;VALUE=DATE:" + d.strftime("%Y%m%d"))
            ls.append("DTEND;VALUE=DATE:" + (last + timedelta(days=1)).strftime("%Y%m%d"))
        ls.append("END:VEVENT")
        return ls
    put_new(cal, account, lines)


def _dt_lines(ymd, hm, dur_min):
    """DTSTART/DTEND lines for a date + optional free start time & minute duration."""
    d = datetime.strptime(ymd, "%Y-%m-%d")
    if hm:
        h, m = hm.split(":")
        start = d.replace(hour=int(h), minute=int(m), tzinfo=LOCAL_TZ)
        end = start + timedelta(minutes=int(dur_min or 60))
        fmt = "%Y%m%dT%H%M%SZ"
        return ["DTSTART:" + start.astimezone(timezone.utc).strftime(fmt),
                "DTEND:" + end.astimezone(timezone.utc).strftime(fmt)]
    return ["DTSTART;VALUE=DATE:" + d.strftime("%Y%m%d"),
            "DTEND;VALUE=DATE:" + (d + timedelta(days=1)).strftime("%Y%m%d")]


def _attach_line(b64, mime):
    """An inline binary attachment line. VALUE=BINARY + ENCODING=BASE64 is what
    RFC 5545 3.8.1.1 asks for; FMTTYPE is what lets a reader tell a picture from
    a PDF without sniffing the bytes."""
    return (f"ATTACH;ENCODING=BASE64;VALUE=BINARY;FMTTYPE={mime or 'image/jpeg'}:"
            + b64.strip())


def _prop_lines(ev):
    """Settable VEVENT lines (summary/location/description/categories/attendees/
    icon) — no BEGIN/END/UID/DTSTAMP/DTSTART/DTEND/RRULE."""
    ls = []
    if ev.get("summary") is not None:
        ls.append("SUMMARY:" + _ics_escape(ev["summary"]))
    if ev.get("location"):
        ls.append("LOCATION:" + _ics_escape(ev["location"]))
    if ev.get("notes"):
        ls.append("DESCRIPTION:" + _ics_escape(ev["notes"]))
    if ev.get("categories"):
        ls.append("CATEGORIES:" + ",".join(_ics_escape(c) for c in ev["categories"]))
    for a in ev.get("attendees", []):
        email = (a.get("email") or "").strip()
        cn = (a.get("name") or "").strip().replace('"', "")
        phone = (a.get("phone") or "").strip().replace('"', "")
        if not (email or phone):
            continue
        params = (f';CN="{cn}"' if cn else "") + (f';X-PHONE="{phone}"' if (phone and email) else "")
        ls.append(f"ATTENDEE{params}:" + (f"mailto:{email}" if email else f"tel:{phone}"))
    if ev.get("icon"):
        ls.append("X-VELORGANIZE-ICON:" + _ics_escape(ev["icon"]))
    # imageData (base64) travels with the event and works everywhere; `image`
    # alone is the old local-path form, kept for callers that have no encoder.
    if ev.get("imageData"):
        ls.append(_attach_line(ev["imageData"], ev.get("imageType")))
    elif ev.get("image"):
        ls.append("X-VELORGANIZE-IMAGE:" + _ics_escape(ev["image"]))
    return ls


def add_event_full(cache, cal_id, ev):
    """Create a VEVENT from a full event dict (summary, ymd, hm, durMin, location,
    notes, categories, attendees, icon)."""
    cal = find_cal(cache, cal_id)
    account = find_account(cal["account"])

    def lines(uid):
        return (["BEGIN:VEVENT", f"UID:{uid}", f"DTSTAMP:{_stamp()}"]
                + _dt_lines(ev["ymd"], ev.get("hm"), ev.get("durMin"))
                + _prop_lines(ev) + ["END:VEVENT"])
    put_new(cal, account, lines)


def toggle_todo(cache, cal_id, href, done):
    """GET-modify-PUT on the raw ICS: swap the STATUS/COMPLETED/PERCENT-COMPLETE
    lines inside the VTODO, leave everything else byte-identical."""
    cal = find_cal(cache, cal_id)
    account = find_account(cal["account"])
    url = full_url(cal["url"], href)
    status, headers, body = http("GET", url, account)
    if status != 200:
        raise RuntimeError(f"GET todo → HTTP {status}")
    etag = headers.get("ETag", "")

    text = _unfold(body.decode())
    out, in_todo, depth = [], False, 0     # depth: nested VALARM etc. — leave those untouched
    for line in text.split("\n"):
        u = line.upper()
        if u.startswith("BEGIN:VTODO"):
            in_todo = True
        elif in_todo and u.startswith("BEGIN:"):
            depth += 1
        elif in_todo and depth > 0 and u.startswith("END:"):
            depth -= 1
        elif u.startswith("END:VTODO"):
            if done:
                out += [f"COMPLETED:{_stamp()}", "PERCENT-COMPLETE:100", "STATUS:COMPLETED"]
            else:
                out.append("STATUS:NEEDS-ACTION")
            in_todo = False
        elif in_todo and depth == 0 and (
                u.startswith("STATUS") or u.startswith("COMPLETED")
                or u.startswith("PERCENT-COMPLETE") or u.startswith("LAST-MODIFIED")):
            continue
        out.append(line)
    ics = "\r\n".join(l for l in out if l.strip() != "") + "\r\n"

    hdrs = {"If-Match": etag} if etag else {}
    status, _, body = http("PUT", url, account, ics, headers=hdrs)
    if status not in (200, 201, 204):
        raise RuntimeError(f"PUT todo → HTTP {status}: {body[:200].decode(errors='replace')}")


def delete_item(cache, cal_id, href):
    cal = find_cal(cache, cal_id)
    account = find_account(cal["account"])
    status, _, _ = http("DELETE", full_url(cal["url"], href), account)
    if status not in (200, 204):
        raise RuntimeError(f"DELETE → HTTP {status}")


def _prop_name(line):
    return line.upper().split(":", 1)[0].split(";", 1)[0]


def _patch_vevent(block, repl, dt_lines):
    """One VEVENT's lines with the patched properties replaced: the old lines are
    dropped and the new ones re-inserted before END:VEVENT, so RRULE / EXDATE /
    VALARM and anything else another client wrote stays byte-intact.

    Depth matters: a VALARM has its own DESCRIPTION and may have its own ATTACH
    (an alarm sound), and neither may be touched."""
    drop = set(repl) | {"LAST-MODIFIED"}
    if dt_lines is not None:
        drop |= {"DTSTART", "DTEND"}
    out, depth = [], 0
    for line in block:
        u = line.upper()
        if u.startswith("BEGIN:VEVENT"):
            pass
        elif u.startswith("BEGIN:"):
            depth += 1
        elif u.startswith("END:VEVENT") and depth == 0:
            for lines_ in repl.values():
                out += lines_
            if dt_lines is not None:
                out += dt_lines
            out.append("LAST-MODIFIED:" + _stamp())
            out.append(line)
            continue
        elif u.startswith("END:"):
            depth -= 1
        elif depth == 0 and _prop_name(line) in drop:
            continue
        out.append(line)
    return out


def update_event(cache, cal_id, href, patch):
    """GET-modify-PUT on a VEVENT. Any field present in `patch` (summary, location,
    notes, categories, attendees, icon, and ymd/hm/durMin for the time) is replaced
    — the property's old lines are dropped at depth 0 and the new ones re-inserted
    before END:VEVENT — while RRULE / EXDATE / VALARM / everything else stays
    byte-intact, so a recurring series keeps recurring."""
    cal = find_cal(cache, cal_id)
    account = find_account(cal["account"])
    url = full_url(cal["url"], href)
    status, headers, body = http("GET", url, account)
    if status != 200:
        raise RuntimeError(f"GET event → HTTP {status}")
    etag = headers.get("ETag", "")

    # Build the replacement lines per property (empty list = clear the property).
    repl = {}
    if "summary" in patch:
        repl["SUMMARY"] = ["SUMMARY:" + _ics_escape(patch.get("summary") or "")]
    if "location" in patch:
        v = patch.get("location") or ""
        repl["LOCATION"] = ["LOCATION:" + _ics_escape(v)] if v else []
    if "notes" in patch:
        v = patch.get("notes") or ""
        repl["DESCRIPTION"] = ["DESCRIPTION:" + _ics_escape(v)] if v else []
    if "categories" in patch:
        cats = patch.get("categories") or []
        repl["CATEGORIES"] = ["CATEGORIES:" + ",".join(_ics_escape(c) for c in cats)] if cats else []
    if "attendees" in patch:
        repl["ATTENDEE"] = _prop_lines({"attendees": patch.get("attendees") or []})
    if "icon" in patch:
        v = patch.get("icon") or ""
        repl["X-VELORGANIZE-ICON"] = ["X-VELORGANIZE-ICON:" + _ics_escape(v)] if v else []
    if "imageData" in patch and patch.get("imageData"):
        repl["ATTACH"] = [_attach_line(patch["imageData"], patch.get("imageType"))]
        repl["X-VELORGANIZE-IMAGE"] = []            # superseded by the attachment
    elif "image" in patch:
        v = patch.get("image") or ""
        if v.startswith(IMAGE_CACHE + os.sep):
            # An extracted attachment handed straight back by a client that only
            # knows paths. Leave the ATTACH alone instead of replacing it with a
            # path that means nothing on any other machine.
            repl["X-VELORGANIZE-IMAGE"] = []
        else:
            repl["ATTACH"] = []
            repl["X-VELORGANIZE-IMAGE"] = ["X-VELORGANIZE-IMAGE:" + _ics_escape(v)] if v else []
    dt_lines = _dt_lines(patch["ymd"], patch.get("hm"), patch.get("durMin")) if patch.get("ymd") else None

    # One resource can hold several VEVENTs: the master plus one per modified
    # occurrence. The patch belongs to the MASTER only — applying it at every
    # END:VEVENT wrote the edited summary into each override as well.
    out, block, in_ev, depth, done = [], None, False, 0, False
    for line in _unfold(body.decode()).split("\n"):
        u = line.upper()
        if not in_ev:
            if u.startswith("BEGIN:VEVENT"):
                in_ev, depth, block = True, 0, [line]
            else:
                out.append(line)
            continue
        block.append(line)
        if u.startswith("BEGIN:"):
            depth += 1
        elif u.startswith("END:VEVENT") and depth == 0:
            in_ev = False
            master = not done and not any(_prop_name(l) == "RECURRENCE-ID" for l in block)
            out += _patch_vevent(block, repl, dt_lines) if master else block
            done = done or master
            block = None
        elif u.startswith("END:"):
            depth -= 1
    if block:                       # unterminated VEVENT: pass it through as-is
        out += block
    ics = "\r\n".join(_fold(l) for l in out if l.strip() != "") + "\r\n"

    hdrs = {"If-Match": etag} if etag else {}
    status, _, body = http("PUT", url, account, ics, headers=hdrs)
    if status not in (200, 201, 204):
        raise RuntimeError(f"PUT event → HTTP {status}: {body[:200].decode(errors='replace')}")


# ── Entry point ───────────────────────────────────────────────────────────────

def _json_arg(v):
    """A JSON argument, or "@<path>" naming a file that holds it. An embedded
    picture is ~160KB of base64 and Linux caps a SINGLE argv entry at 128KB, so
    anything carrying an attachment has to arrive as a file."""
    if v.startswith("@"):
        with open(v[1:], encoding="utf-8") as f:
            return json.load(f)
    return json.loads(v)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "load"
    args = sys.argv[2:]

    if cmd == "load":
        emit(load_cache())
        return

    if cmd == "sync":
        emit(sync())
        return

    if cmd == "add-account":
        account = {"name": os.environ.get("CD_NAME", "").strip(),
                   "url": os.environ.get("CD_URL", "").strip(),
                   "username": os.environ.get("CD_USER", "").strip(),
                   "password": os.environ.get("CD_PASS", "")}
        if not (account["name"] and account["url"] and account["username"]):
            raise RuntimeError("add-account needs CD_NAME, CD_URL, CD_USER, CD_PASS")
        discover_calendars(account)          # validate credentials before saving
        accounts = [a for a in load_accounts() if a["name"] != account["name"]]
        accounts.append(account)
        save_accounts(accounts)
        emit(sync())
        return

    if cmd == "remove-account":
        save_accounts([a for a in load_accounts() if a["name"] != args[0]])
        emit(sync())
        return

    if cmd == "rename-account":
        old, new = args[0], (args[1] or "").strip()
        if new:
            accs = load_accounts()
            for a in accs:
                if a["name"] == old:
                    a["name"] = new
            save_accounts(accs)
        emit(sync())
        return

    cache = load_cache()
    try:
        if cmd == "add-todo":
            add_todo(cache, args[0], args[1], args[2] if len(args) > 2 else None)
        elif cmd == "toggle-todo":
            toggle_todo(cache, args[0], args[1], args[2] == "1")
        elif cmd == "add-event":
            add_event(cache, args[0], args[1], args[2],
                      args[3] if len(args) > 3 and args[3] else None,
                      int(args[4]) if len(args) > 4 and args[4] else 60,
                      args[5] if len(args) > 5 and args[5] else None,
                      args[6] if len(args) > 6 and args[6] else None)
        elif cmd == "add-event-full":
            add_event_full(cache, args[0], _json_arg(args[1]))
        elif cmd == "delete-item":
            delete_item(cache, args[0], args[1])
        elif cmd == "update-event":
            update_event(cache, args[0], args[1], _json_arg(args[2]))
        else:
            raise RuntimeError("unknown command " + cmd)
        emit(sync())
    except Exception as e:
        cache["lastError"] = str(e)
        emit(cache)
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        cache = load_cache()
        cache["lastError"] = str(exc)
        emit(cache)
        sys.exit(1)
