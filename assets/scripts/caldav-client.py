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
  add-event <calId> <summary> <YYYY-MM-DD> [HH:MM] [durationMin]
  delete-item <calId> <href>

calId = "<account name>|<calendar href>". Accounts live in
$VELUMERON_USER_DIR/gui/caldav-accounts.json (chmod 600 — use app passwords);
the cache in ~/.cache/velumeron/caldav-cache.json.
"""

import base64
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
    return urllib.parse.urljoin(base, href)


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
                    "location": _text(src, "LOCATION"),
                    "allDay":   all_day2,
                    "startMs":  int(s.timestamp() * 1000),
                    "endMs":    int(e.timestamp() * 1000),
                    "recurring": bool(vr),
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
                "summary": _text(c, "SUMMARY") or "(untitled)",
                "location": _text(c, "LOCATION"), "allDay": ad,
                "startMs": int(s.timestamp() * 1000), "endMs": int(e.timestamp() * 1000),
                "recurring": True,
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
    for account in load_accounts():
        entry = {"name": account["name"], "url": account["url"],
                 "username": account["username"], "ok": True, "error": ""}
        try:
            for cal in discover_calendars(account):
                cache["calendars"].append(cal)
                try:
                    if cal["vevent"]:
                        cache["events"] += shape_events(
                            cal, _report(cal, account, "VEVENT", tr), win_start, win_end)
                    if cal["vtodo"]:
                        cache["todos"] += shape_todos(cal, _report(cal, account, "VTODO"))
                except Exception as e:
                    entry["ok"] = False
                    entry["error"] = f"{cal['name']}: {e}"
        except Exception as e:
            entry["ok"] = False
            entry["error"] = str(e)
        cache["accounts"].append(entry)

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


def put_new(cal, account, component_lines):
    uid = str(uuid.uuid4())
    ics = "\r\n".join([
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


def add_event(cache, cal_id, summary, ymd, hm=None, duration_min=60):
    cal = find_cal(cache, cal_id)
    account = find_account(cal["account"])
    d = datetime.strptime(ymd, "%Y-%m-%d")

    def lines(uid):
        ls = ["BEGIN:VEVENT", f"UID:{uid}", f"DTSTAMP:{_stamp()}",
              f"SUMMARY:{_ics_escape(summary)}"]
        if hm:
            h, m = hm.split(":")
            start = d.replace(hour=int(h), minute=int(m), tzinfo=LOCAL_TZ)
            end = start + timedelta(minutes=duration_min)
            fmt = "%Y%m%dT%H%M%SZ"
            ls.append("DTSTART:" + start.astimezone(timezone.utc).strftime(fmt))
            ls.append("DTEND:" + end.astimezone(timezone.utc).strftime(fmt))
        else:
            ls.append("DTSTART;VALUE=DATE:" + d.strftime("%Y%m%d"))
            ls.append("DTEND;VALUE=DATE:" + (d + timedelta(days=1)).strftime("%Y%m%d"))
        ls.append("END:VEVENT")
        return ls
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


# ── Entry point ───────────────────────────────────────────────────────────────

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

    cache = load_cache()
    try:
        if cmd == "add-todo":
            add_todo(cache, args[0], args[1], args[2] if len(args) > 2 else None)
        elif cmd == "toggle-todo":
            toggle_todo(cache, args[0], args[1], args[2] == "1")
        elif cmd == "add-event":
            add_event(cache, args[0], args[1], args[2],
                      args[3] if len(args) > 3 and args[3] else None,
                      int(args[4]) if len(args) > 4 else 60)
        elif cmd == "delete-item":
            delete_item(cache, args[0], args[1])
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
