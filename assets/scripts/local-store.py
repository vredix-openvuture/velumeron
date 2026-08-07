#!/usr/bin/env python3
"""Local calendars and task lists — no server, no account (stdlib only).

The third todo/calendar backend next to Vikunja (vikunja-client.py) and CalDAV
(caldav-client.py): lists and items that live on this machine only. Same contract
as its two siblings — every command prints the FULL store as JSON on stdout, so
the QML service has one parse path for load and every mutation.

THE STORE IS SHARED WITH DISPONERA. The app grew local lists first
(src/disponera/local.py, blueprint #7) and its on-disk schema is the spec here;
this script must keep writing exactly that shape. Disponera reads and writes the
same file in-process, so the shell's calendar menu and the app show the same
local lists by construction — the way they already share caldav-accounts.json.
Both sides watch the file, so a change on either side shows up live on the other.

Schema ($VELUMERON_USER_DIR/gui/local.json):
  lists     [{ id, name, kind: "todo"|"calendar", color }]
  items     [{ id, listId, title, ymd, hm, durMin, done, doneMs, priority,
               notes, location, categories, attendees, icon, image }]
  ics       [{ id, name, url, color }]   — Disponera's read-only feeds (untouched here)
  roles     { account: "both"|"tasks"|"calendar" }   — Disponera's copy (untouched here)
  eventTags [{ name, color }]

An item is a todo or an event depending on its list's kind: a "todo" list's items
carry done/doneMs/priority, a "calendar" list's items carry hm/durMin. Unknown
keys — anything a newer Disponera writes — survive every mutation untouched, so
neither side has to know the other's extras.

Commands:
  load                                 print the store, no changes
  add-list <name> <kind> [color]       kind = todo | calendar
  rename-list <id> <name>
  set-list-color <id> <color>
  delete-list <id>                     also drops the list's items
  add-todo <listId> <title> [ymd] [hm] [jsonExtra]     extra = {priority,notes}
  add-event <listId> <jsonEvent>       {summary,ymd,hm,durMin,notes,location,…}
  update-item <id> <jsonPatch>         any subset of the item keys (+ listId to move)
  toggle-item <id>
  delete-item <id>
"""

import json
import os
import shutil
import sys
import time
import uuid

VALID_KINDS = ("todo", "calendar")


def user_dir():
    u = os.environ.get("VELUMERON_USER_DIR")
    if u:
        return u
    xdg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(xdg, "velumeron")


STORE_PATH = os.path.join(user_dir(), "gui", "local.json")

# Where Disponera kept the store before it moved next to the CalDAV accounts.
# Copied over (never moved) the first time this runs, so an older app build that
# still reads the old path keeps working off its own file instead of losing data.
LEGACY_PATH = os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
    "disponera", "local.json")

EMPTY = {"lists": [], "items": [], "ics": [], "roles": {}, "eventTags": []}


def load_store():
    if not os.path.exists(STORE_PATH) and os.path.exists(LEGACY_PATH):
        try:
            os.makedirs(os.path.dirname(STORE_PATH), exist_ok=True)
            shutil.copyfile(LEGACY_PATH, STORE_PATH)
        except OSError:
            pass
    try:
        with open(STORE_PATH) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return dict(EMPTY)
    if not isinstance(d, dict):
        return dict(EMPTY)
    for k, v in EMPTY.items():
        d.setdefault(k, type(v)())
    return d


def save_store(store):
    os.makedirs(os.path.dirname(STORE_PATH), exist_ok=True)
    tmp = STORE_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(store, f, indent=2)
    os.replace(tmp, STORE_PATH)


def emit(store):
    json.dump(store, sys.stdout)
    sys.stdout.write("\n")


def new_id():
    return uuid.uuid4().hex[:8]        # Disponera's id format — keep it


def now_ms():
    return int(time.time() * 1000)


def find_list(store, list_id):
    return next((l for l in store["lists"] if l.get("id") == list_id), None)


def find_item(store, item_id):
    return next((i for i in store["items"] if i.get("id") == item_id), None)


# ── List CRUD ─────────────────────────────────────────────────────────────────

def add_list(store, name, kind, color=""):
    name = (name or "").strip()
    if not name:
        return
    store["lists"].append({"id": new_id(), "name": name,
                           "kind": kind if kind in VALID_KINDS else "todo",
                           "color": color or ""})


def rename_list(store, list_id, name):
    l = find_list(store, list_id)
    if l is not None and (name or "").strip():
        l["name"] = name.strip()


def set_list_color(store, list_id, color):
    l = find_list(store, list_id)
    if l is not None:
        l["color"] = color or ""


def delete_list(store, list_id):
    store["lists"] = [l for l in store["lists"] if l.get("id") != list_id]
    store["items"] = [i for i in store["items"] if i.get("listId") != list_id]


# ── Item CRUD ─────────────────────────────────────────────────────────────────

def add_todo(store, list_id, title, ymd="", hm="", extra=None):
    """extra (optional JSON tail) carries the full editor's {priority, notes} —
    a plain quick-add omits it, mirroring vikunja-client.py's add-task."""
    title = (title or "").strip()
    if not title or find_list(store, list_id) is None:
        return
    extra = extra or {}
    try:
        prio = int(extra.get("priority") or 0)
    except (TypeError, ValueError):
        prio = 0
    store["items"].append({"id": new_id(), "listId": list_id, "title": title,
                           "ymd": ymd or "", "hm": hm or "", "done": False,
                           "doneMs": 0, "priority": prio,
                           "notes": extra.get("notes") or ""})


def add_event(store, list_id, ev):
    title = (ev.get("summary") or ev.get("title") or "").strip()
    if not title or not ev.get("ymd") or find_list(store, list_id) is None:
        return
    store["items"].append({
        "id": new_id(), "listId": list_id, "title": title, "ymd": ev["ymd"],
        "hm": ev.get("hm") or "", "durMin": int(ev.get("durMin") or 60),
        "endYmd": ev.get("endYmd") or "",
        "notes": ev.get("notes") or "", "location": ev.get("location") or "",
        "categories": list(ev.get("categories") or []),
        "attendees": [dict(a) for a in (ev.get("attendees") or [])],
        "icon": ev.get("icon") or "", "image": ev.get("image") or ""})


# Keys a patch may set, and how to coerce them.
_PATCH_STR = ("title", "ymd", "hm", "endYmd", "notes", "location", "icon", "image")
_PATCH_INT = ("priority", "durMin")


def update_item(store, item_id, patch):
    it = find_item(store, item_id)
    if it is None:
        return
    if "summary" in patch:                 # the event editor calls the title "summary"
        it["title"] = patch["summary"]
    if "listId" in patch:                  # move to another list (same kind, or it vanishes)
        if find_list(store, patch["listId"]) is not None:
            it["listId"] = patch["listId"]
    for k in _PATCH_STR:
        if k in patch:
            it[k] = patch[k] or ""
    for k in _PATCH_INT:
        if k in patch:
            try:
                it[k] = int(patch[k] or 0)
            except (TypeError, ValueError):
                it[k] = 0
    if "done" in patch:
        it["done"] = bool(patch["done"])
        it["doneMs"] = now_ms() if it["done"] else 0
    if "categories" in patch:
        it["categories"] = list(patch["categories"] or [])
    if "attendees" in patch:
        it["attendees"] = [dict(a) for a in (patch["attendees"] or [])]


def toggle_item(store, item_id):
    it = find_item(store, item_id)
    if it is not None:
        it["done"] = not it.get("done")
        it["doneMs"] = now_ms() if it["done"] else 0


def delete_item(store, item_id):
    store["items"] = [i for i in store["items"] if i.get("id") != item_id]


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    argv = sys.argv[1:]
    if not argv:
        sys.stderr.write(__doc__)
        return 2
    cmd, args = argv[0], argv[1:]

    def arg(n, default=""):
        return args[n] if len(args) > n else default

    def as_json(n):
        try:
            return json.loads(arg(n) or "{}")
        except ValueError:
            return {}

    store = load_store()
    if cmd == "load":
        emit(store)
        return 0

    handlers = {
        "add-list":       lambda: add_list(store, arg(0), arg(1), arg(2)),
        "rename-list":    lambda: rename_list(store, arg(0), arg(1)),
        "set-list-color": lambda: set_list_color(store, arg(0), arg(1)),
        "delete-list":    lambda: delete_list(store, arg(0)),
        "add-todo":       lambda: add_todo(store, arg(0), arg(1), arg(2), arg(3), as_json(4)),
        "add-event":      lambda: add_event(store, arg(0), as_json(1)),
        "update-item":    lambda: update_item(store, arg(0), as_json(1)),
        "toggle-item":    lambda: toggle_item(store, arg(0)),
        "delete-item":    lambda: delete_item(store, arg(0)),
    }
    if cmd not in handlers:
        sys.stderr.write("unknown command: %s\n" % cmd)
        return 2
    handlers[cmd]()
    save_store(store)
    emit(store)
    return 0


if __name__ == "__main__":
    sys.exit(main())
