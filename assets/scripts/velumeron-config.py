#!/usr/bin/env python3
"""velumeron-config — the single place that reconciles settings.json with the active template.

A *template* is a complete snapshot of settings.json plus metadata. The live settings.json stays
the effective config (VtlConfig / Colors / every surface read it unchanged); a template just records
a snapshot of it. One `sync` call — driven by a watcher on settings.json — makes the whole thing
copy-on-write: whenever settings.json diverges from the active template, the change is persisted into
that template; if the active template is a shipped built-in, it is first forked into a private user
copy so the built-in is never mutated.

Layout:
  $VELUMERON_DIR/assets/templates/<id>/template.json      built-in, READ-ONLY (shipped in the repo)
  $VELUMERON_USER_DIR/templates/<id>/template.json         user, writable
  $VELUMERON_USER_DIR/gui/settings.json                    effective config
  $VELUMERON_USER_DIR/active-template.json                 { "id": ..., "source": "builtin"|"user" }

Verbs:
  sync                       reconcile settings.json -> active template (fork-if-builtin). Idempotent.
  activate <source> <id>     point active at a template and apply its settings to settings.json.
  list                       print JSON { active, builtin[], user[] } for the UI.
  duplicate <source> <id> [name]   copy a template into a new user template (does not activate).
  new [name]                 snapshot the current settings.json into a new user template.
  rename <id> <name>         rename a user template (display name only; id/dir stays stable).
  delete <id>                remove a user template (falls back to Mirobo if it was active).
  init                       one-time migration: adopt the existing settings.json as a user template,
                             or point active at the mirobo built-in. No-op if already initialised.
"""

import json
import os
import re
import sys
import tempfile

# ── Paths ────────────────────────────────────────────────────────────────────────────────────────


def _env(name, default=""):
    v = os.environ.get(name)
    return v if v else default


def repo_dir():
    d = _env("VELUMERON_DIR")
    if d:
        return d
    # Fall back to this file's location: assets/scripts/velumeron-config.py -> repo root
    return os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", ".."))


def user_dir():
    d = _env("VELUMERON_USER_DIR")
    if d:
        return d
    xdg = _env("XDG_CONFIG_HOME")
    base = xdg if xdg else os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "velumeron")


def builtin_root():
    return os.path.join(repo_dir(), "assets", "templates")


def user_root():
    return os.path.join(user_dir(), "templates")


def settings_path():
    return os.path.join(user_dir(), "gui", "settings.json")


def active_path():
    return os.path.join(user_dir(), "active-template.json")


def template_path(source, tid):
    root = builtin_root() if source == "builtin" else user_root()
    return os.path.join(root, tid, "template.json")


# ── JSON I/O (atomic — the shell polls these files, so never expose a partial write) ───────────────


def read_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            txt = f.read().strip()
        return json.loads(txt) if txt else default
    except (OSError, ValueError):
        return default


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(json.dumps(obj, indent=2, ensure_ascii=False))
            f.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def write_settings(obj):
    """settings.json is written IN PLACE (same inode) — it matches the existing GUI pages and keeps
    the shell's FileView watch on the path valid (an atomic replace would swap the inode)."""
    p = settings_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(json.dumps(obj, indent=2, ensure_ascii=False))
        f.write("\n")


# ── Template helpers ───────────────────────────────────────────────────────────────────────────────


def slugify(name):
    s = re.sub(r"[^a-z0-9]+", "-", ("" + name).strip().lower()).strip("-")
    return s or "template"


def unique_user_id(base):
    root = user_root()
    tid = base
    n = 2
    while os.path.exists(os.path.join(root, tid)):
        tid = "%s-%d" % (base, n)
        n += 1
    return tid


def load_template(source, tid):
    return read_json(template_path(source, tid), None)


def scan(source):
    root = builtin_root() if source == "builtin" else user_root()
    out = []
    if not os.path.isdir(root):
        return out
    for tid in sorted(os.listdir(root)):
        t = read_json(os.path.join(root, tid, "template.json"), None)
        if not isinstance(t, dict):
            continue
        out.append({
            "id": t.get("id", tid),
            "name": t.get("name", tid),
            "author": t.get("author", ""),
            "builtin": source == "builtin",
            "source": source,
        })
    return out


def get_active():
    a = read_json(active_path(), None)
    if isinstance(a, dict) and a.get("id"):
        return {"id": a["id"], "source": a.get("source", "user")}
    return None


def set_active(tid, source):
    write_json(active_path(), {"id": tid, "source": source})


def write_user_template(tid, name, settings, author="you"):
    write_json(template_path("user", tid), {
        "id": tid,
        "name": name,
        "author": author,
        "builtin": False,
        "version": 1,
        "settings": settings,
    })


# ── Verbs ────────────────────────────────────────────────────────────────────────────────────────


def verb_init():
    active = get_active()
    if active:
        # Self-heal a wedged first run: an active BUILTIN whose settings never
        # landed (empty/missing settings.json) means the device is running bare
        # QML defaults — re-apply the template instead of bailing with "already".
        # User templates are never overwritten here.
        if active["source"] == "builtin" and not read_json(settings_path(), {}):
            tmpl = load_template("builtin", active["id"])
            if tmpl is not None and tmpl.get("settings"):
                write_settings(tmpl["settings"])
                print("init:healed:%s" % active["id"])
                return
        print("init:already")
        return
    settings = read_json(settings_path(), {})
    # If the live config already matches a shipped built-in, adopt that built-in (no needless copy).
    for t in scan("builtin"):
        bt = load_template("builtin", t["id"])
        if bt is not None and bt.get("settings", {}) == settings:
            set_active(t["id"], "builtin")
            print("init:builtin:%s" % t["id"])
            return
    if not settings:
        # Fresh install: don't just point at the shipped template — APPLY it, so a
        # new device starts with the curated bar/style instead of bare QML defaults.
        # Only claim the template active once it actually loaded: marking it active
        # with the settings unwritten wedged the device on bare defaults forever
        # (every later init saw "already"). If the files are missing, leave the
        # state untouched so the next boot retries.
        mirobo = load_template("builtin", "mirobo")
        if mirobo is None:
            print("init:mirobo-missing", file=sys.stderr)
            return
        set_active("mirobo", "builtin")
        write_settings(mirobo.get("settings", {}))
        print("init:mirobo")
        return
    # Genuinely custom config that matches no preset -> keep it as a private user template.
    tid = unique_user_id("mein-setup")
    write_user_template(tid, "Mein Setup", settings)
    set_active(tid, "user")
    print("init:migrated:%s" % tid)


def verb_sync():
    active = get_active()
    if not active:
        verb_init()
        active = get_active()
    if not active:
        print("sync:noactive")
        return
    tmpl = load_template(active["source"], active["id"])
    if tmpl is None:
        # Active template vanished (e.g. deleted builtin) — fall back to mirobo,
        # APPLYING it (pointing without writing left the device on bare defaults).
        mirobo = load_template("builtin", "mirobo")
        if mirobo is not None:
            set_active("mirobo", "builtin")
            write_settings(mirobo.get("settings", {}))
        print("sync:reset")
        return
    cur = read_json(settings_path(), {})
    if cur == tmpl.get("settings", {}):
        print("sync:insync")
        return
    if not cur and active["source"] == "builtin":
        # Empty settings.json under an active builtin is a wedged state, never a
        # deliberate config — re-apply the template instead of forking an empty copy.
        write_settings(tmpl.get("settings", {}))
        print("sync:healed:%s" % active["id"])
        return
    if active["source"] == "builtin":
        base = slugify(tmpl.get("name", active["id"])) + "-kopie"
        tid = unique_user_id(base)
        write_user_template(tid, tmpl.get("name", active["id"]) + " (Kopie)", cur,
                            author=tmpl.get("author", "you"))
        set_active(tid, "user")
        print("sync:forked:%s" % tid)
    else:
        tmpl["settings"] = cur
        write_json(template_path("user", active["id"]), tmpl)
        print("sync:synced:%s" % active["id"])


def verb_activate(source, tid):
    tmpl = load_template(source, tid)
    if tmpl is None:
        print("activate:notfound", file=sys.stderr)
        sys.exit(1)
    set_active(tid, source)                       # active first, so a following sync is a no-op
    write_settings(tmpl.get("settings", {}))      # full replace -> unset keys revert to defaults
    print("activate:%s:%s" % (source, tid))


def verb_list():
    print(json.dumps({
        "active": get_active(),
        "builtin": scan("builtin"),
        "user": scan("user"),
    }))


def verb_duplicate(source, tid, name=None):
    tmpl = load_template(source, tid)
    if tmpl is None:
        print("duplicate:notfound", file=sys.stderr)
        sys.exit(1)
    name = name or (tmpl.get("name", tid) + " (Kopie)")
    newid = unique_user_id(slugify(name))
    write_user_template(newid, name, dict(tmpl.get("settings", {})),
                        author=tmpl.get("author", "you"))
    print("duplicate:%s" % newid)


def verb_new(name=None):
    name = name or "Neues Template"
    newid = unique_user_id(slugify(name))
    write_user_template(newid, name, read_json(settings_path(), {}))
    print("new:%s" % newid)


def verb_rename(tid, name):
    tmpl = load_template("user", tid)
    if tmpl is None:
        print("rename:notfound", file=sys.stderr)
        sys.exit(1)
    tmpl["name"] = name
    write_json(template_path("user", tid), tmpl)
    print("rename:%s" % tid)


def verb_delete(tid):
    import shutil
    d = os.path.join(user_root(), tid)
    if not os.path.isdir(d):
        print("delete:notfound", file=sys.stderr)
        sys.exit(1)
    active = get_active()
    shutil.rmtree(d, ignore_errors=True)
    if active and active["source"] == "user" and active["id"] == tid:
        verb_activate("builtin", "mirobo")
    print("delete:%s" % tid)


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: velumeron-config <verb> [...]", file=sys.stderr)
        sys.exit(2)
    verb, rest = args[0], args[1:]
    dispatch = {
        "sync": lambda: verb_sync(),
        "init": lambda: verb_init(),
        "list": lambda: verb_list(),
        "activate": lambda: verb_activate(rest[0], rest[1]),
        "duplicate": lambda: verb_duplicate(rest[0], rest[1], rest[2] if len(rest) > 2 else None),
        "new": lambda: verb_new(rest[0] if rest else None),
        "rename": lambda: verb_rename(rest[0], rest[1]),
        "delete": lambda: verb_delete(rest[0]),
    }
    fn = dispatch.get(verb)
    if not fn:
        print("unknown verb: %s" % verb, file=sys.stderr)
        sys.exit(2)
    fn()


if __name__ == "__main__":
    main()
