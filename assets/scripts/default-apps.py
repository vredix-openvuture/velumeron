#!/usr/bin/env python3
"""default-apps.py — which application opens which kind of file, system-wide.

This is the freedesktop MIME default, NOT a velumeron setting: everything on the machine that
calls xdg-open (our own screenshot notification, a browser download, a file manager) ends up
here, and so does every other desktop's control panel. So nothing is stored in velumeron's own
config — reads follow the mimeapps.list chain the spec defines, and writes go through
`xdg-mime default`, which is the same tool a terminal user would reach for.

Commands
    list                 → JSON: every category with its current default and the installed
                           applications that declare they can open it
    set KEY DESKTOP_ID   → make DESKTOP_ID the default for every MIME type in that category,
                           then print the same JSON as `list`

A "category" is a group of MIME types that a person thinks of as one choice ("images", "video").
Setting one writes ALL of its types, which is the whole point: image/png opening in the browser
while image/jpeg opens in a viewer is the state this page exists to end.
"""

import json
import os
import subprocess
import sys

# ── Categories ──────────────────────────────────────────────────────────────────────────────────
# The first MIME type of each list is the one whose default is REPORTED (they are set together, so
# they normally agree; when they don't, `mixed` says so). Types are the ones actually seen in the
# wild — a longer list only means more entries in mimeapps.list that no file ever matches.
#
# "match" narrows WHO IS OFFERED without narrowing what gets written. The browser is the case that
# needs it: setting one must still claim text/html, but merely handling text/html does not make an
# app a browser. Every text editor with a syntax mode for HTML declares it, so micro and
# KImageMapEditor turned up in the browser picker. Requiring the http/https scheme handlers instead
# asks the only question that actually identifies a browser: can you open a link? Absent, the
# candidate test falls back to "mimes", which is right for every other category.
CATEGORIES = (
    {"key": "browser", "title": "Web browser", "icon": "\U000f059f",
     "hint": "http and https links, and local HTML files.",
     "mimes": ["x-scheme-handler/http", "x-scheme-handler/https",
               "text/html", "application/xhtml+xml"],
     "match": ["x-scheme-handler/http", "x-scheme-handler/https"]},
    {"key": "mail", "title": "Email", "icon": "\U000f01ee",
     "hint": "mailto: links.",
     "mimes": ["x-scheme-handler/mailto"]},
    {"key": "files", "title": "File manager", "icon": "\U000f024b",
     "hint": "Folders — including the ones velumeron opens for you.",
     "mimes": ["inode/directory"]},
    {"key": "images", "title": "Images", "icon": "\U000f02e9",
     "hint": "PNG, JPEG, GIF, WebP, BMP, TIFF — this is what a screenshot notification opens.",
     "mimes": ["image/png", "image/jpeg", "image/gif", "image/webp",
               "image/bmp", "image/tiff"]},
    {"key": "audio", "title": "Audio", "icon": "\U000f075a",
     "hint": "MP3, FLAC, Ogg, WAV, AAC.",
     "mimes": ["audio/mpeg", "audio/flac", "audio/x-vorbis+ogg", "audio/ogg",
               "audio/mp4", "audio/x-wav", "audio/aac", "audio/x-opus+ogg"]},
    {"key": "video", "title": "Video", "icon": "\U000f0381",
     "hint": "MP4, Matroska, WebM, AVI, MOV.",
     "mimes": ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime",
               "video/x-msvideo", "video/mpeg"]},
    {"key": "text", "title": "Text files", "icon": "\U000f0219",
     "hint": "Plain text, Markdown, JSON, shell scripts.",
     "mimes": ["text/plain", "text/markdown", "application/json",
               "application/x-shellscript"]},
    {"key": "pdf", "title": "PDF documents", "icon": "\U000f0226",
     "hint": "application/pdf.",
     "mimes": ["application/pdf"]},
    {"key": "archive", "title": "Archives", "icon": "\U000f06eb",
     "hint": "ZIP, tar, gzip, 7z, RAR.",
     "mimes": ["application/zip", "application/x-tar", "application/gzip",
               "application/x-7z-compressed", "application/vnd.rar", "application/x-xz"]},
    {"key": "calendar", "title": "Calendar files", "icon": "\U000f00ed",
     "hint": "ICS invitations and calendar exports.",
     "mimes": ["text/calendar"]},
)


def _dirs(var, fallback):
    return [d for d in (os.environ.get(var) or fallback).split(":") if d]


def data_dirs():
    home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return [home] + _dirs("XDG_DATA_DIRS", "/usr/local/share:/usr/share")


def config_dirs():
    home = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return [home] + _dirs("XDG_CONFIG_DIRS", "/etc/xdg")


def locales():
    """Name[de_DE] → Name[de] → Name, from the session's own locale."""
    out = []
    loc = (os.environ.get("LC_MESSAGES") or os.environ.get("LC_ALL")
           or os.environ.get("LANG") or "")
    loc = loc.split(".")[0].split("@")[0]
    if loc and loc != "C" and loc != "POSIX":
        out.append(loc)
        if "_" in loc:
            out.append(loc.split("_")[0])
    return out


LOCALES = locales()


# ── .desktop scanning ───────────────────────────────────────────────────────────────────────────
def parse_desktop(path):
    """The [Desktop Entry] group only. Later groups (actions) are irrelevant here."""
    out = {}
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            in_entry = False
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("["):
                    if in_entry:
                        break
                    in_entry = line == "[Desktop Entry]"
                    continue
                if not in_entry or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
    except OSError:
        return {}
    return out


def localized(entry, key):
    for loc in LOCALES:
        v = entry.get("%s[%s]" % (key, loc))
        if v:
            return v
    return entry.get(key, "")


def scan_apps():
    """desktop id → app record. Earlier data dirs win, which is how a user override works."""
    apps = {}
    for base in data_dirs():
        root = os.path.join(base, "applications")
        if not os.path.isdir(root):
            continue
        for dirpath, _dirnames, filenames in os.walk(root):
            for fn in filenames:
                if not fn.endswith(".desktop"):
                    continue
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, root)
                # Subdirectories become part of the id with '-' (kde/foo.desktop → kde-foo.desktop).
                did = rel.replace(os.sep, "-")
                if did in apps:
                    continue
                e = parse_desktop(full)
                if not e or e.get("Type", "Application") != "Application":
                    continue
                mimes = [m for m in e.get("MimeType", "").split(";") if m]
                try:
                    pref = int(e.get("InitialPreference", "0"))
                except ValueError:
                    pref = 0
                apps[did] = {
                    "id": did,
                    "name": localized(e, "Name") or did[:-8],
                    "generic": localized(e, "GenericName"),
                    "icon": e.get("Icon", ""),
                    "mimes": set(mimes),
                    "pref": pref,
                    "hidden": (e.get("Hidden", "").lower() == "true"
                               or e.get("NoDisplay", "").lower() == "true"),
                    "path": full,
                }
    return apps


# ── mimeapps.list chain (the read side of the spec) ─────────────────────────────────────────────
def parse_mimeapps(path):
    groups = {"Default Applications": {}, "Added Associations": {}, "Removed Associations": {}}
    cur = None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    cur = line[1:-1]
                    continue
                if cur not in groups or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                groups[cur][k.strip()] = [x for x in v.strip().split(";") if x]
    except OSError:
        return None
    return groups


def mimeapps_chain():
    """Every mimeapps.list that counts, in precedence order (spec: config dirs, then data dirs)."""
    desktops = [d.lower() for d in (os.environ.get("XDG_CURRENT_DESKTOP") or "").split(":") if d]
    out = []
    for d in config_dirs():
        out += [os.path.join(d, "%s-mimeapps.list" % de) for de in desktops]
        out.append(os.path.join(d, "mimeapps.list"))
    for d in data_dirs():
        a = os.path.join(d, "applications")
        out += [os.path.join(a, "%s-mimeapps.list" % de) for de in desktops]
        out.append(os.path.join(a, "mimeapps.list"))
    return out


def trader_map():
    """mime → [ids] from defaults.list / mimeinfo.cache, user data dir first. This is the same
    "what would open it if nobody ever chose" table xdg-mime greps, and NOT the [Added
    Associations] of mimeapps.list — xdg-mime ignores those when resolving a default, so reading
    them here would make this page disagree with the system it is supposed to be showing."""
    out = {}
    for d in data_dirs():
        for fn in ("defaults.list", "mimeinfo.cache"):
            p = os.path.join(d, "applications", fn)
            try:
                fh = open(p, "r", encoding="utf-8", errors="replace")
            except OSError:
                continue
            with fh:
                for line in fh:
                    line = line.strip()
                    if "=" not in line or line.startswith("["):
                        continue
                    k, v = line.split("=", 1)
                    k = k.strip()
                    for i in [x for x in v.split(";") if x]:
                        out.setdefault(k, [])
                        if i not in out[k]:
                            out[k].append(i)
    return out


def defaults_for(mimes, apps):
    """mime → desktop id, resolved the way `xdg-mime query default` resolves it: the
    mimeapps.list chain's [Default Applications], then the association caches, then the
    highest-InitialPreference application that declares the type."""
    chain = [(p, parse_mimeapps(p)) for p in mimeapps_chain()]
    chain = [(p, g) for p, g in chain if g]
    trader = trader_map()
    out = {}
    for mime in mimes:
        found = ""
        for _p, g in chain:
            for did in g["Default Applications"].get(mime, []):
                if did in apps:
                    found = did
                    break
            if found:
                break
        if not found:
            for did in trader.get(mime, []):
                if did in apps:
                    found = did
                    break
        if not found:
            best = -1
            for did, a in apps.items():
                if mime in a["mimes"] and a["pref"] > best:
                    best = a["pref"]
                    found = did
        out[mime] = found
    return out


# ── list / set ──────────────────────────────────────────────────────────────────────────────────
def build_list():
    apps = scan_apps()
    all_mimes = []
    for c in CATEGORIES:
        all_mimes += c["mimes"]
    cur = defaults_for(all_mimes, apps)

    cats = []
    for c in CATEGORIES:
        primary = c["mimes"][0]
        current = cur.get(primary, "")
        picked = [cur.get(m, "") for m in c["mimes"]]
        mixed = len({p for p in picked if p}) > 1
        # A candidate is an app that SAYS it handles one of the IDENTIFYING types (see "match"
        # above; most categories identify on the same list they write). The current default is
        # always offered too, even when it says nothing — that is how it got there, and dropping it
        # from its own list would read as "nothing is set".
        ident = c.get("match") or c["mimes"]
        cands = []
        for did, a in apps.items():
            if a["hidden"] and did != current:
                continue
            if a["mimes"].isdisjoint(ident) and did != current:
                continue
            cands.append({"id": did, "name": a["name"], "icon": a["icon"],
                          "generic": a["generic"]})
        cands.sort(key=lambda x: (x["name"].lower(), x["id"]))
        cats.append({
            "key": c["key"], "title": c["title"], "icon": c["icon"], "hint": c["hint"],
            "mimes": c["mimes"],
            "current": current,
            "currentName": apps[current]["name"] if current in apps else "",
            "currentIcon": apps[current]["icon"] if current in apps else "",
            "mixed": mixed,
            "perMime": {m: cur.get(m, "") for m in c["mimes"]},
            "candidates": cands,
        })
    return {"categories": cats}


def category(key):
    for c in CATEGORIES:
        if c["key"] == key:
            return c
    return None


def cmd_set(key, did):
    c = category(key)
    if not c:
        return "unknown category: %s" % key
    if not did.endswith(".desktop"):
        return "not a desktop id: %s" % did
    if did not in scan_apps():
        return "no such application: %s" % did
    try:
        r = subprocess.run(["xdg-mime", "default", did] + c["mimes"],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError) as e:
        return "xdg-mime failed: %s" % e
    if r.returncode != 0:
        return (r.stderr or r.stdout or "xdg-mime failed").strip()
    # The browser is the one role with a second registry: xdg-settings also carries it into the
    # desktop-specific slot some toolkits read instead of mimeapps.list. Best effort — a failure
    # here does not undo the MIME defaults that just landed.
    if key == "browser":
        try:
            subprocess.run(["xdg-settings", "set", "default-web-browser", did],
                           capture_output=True, text=True, timeout=20)
        except (OSError, subprocess.SubprocessError):
            pass
    return ""


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "list"
    err = ""
    if cmd == "list":
        pass
    elif cmd == "set":
        if len(argv) < 4:
            print(json.dumps({"error": "usage: default-apps.py set KEY DESKTOP_ID"}))
            return 2
        err = cmd_set(argv[2], argv[3])
    else:
        print(json.dumps({"error": "usage: default-apps.py list|set KEY DESKTOP_ID"}))
        return 2
    out = build_list()
    if err:
        out["error"] = err
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
