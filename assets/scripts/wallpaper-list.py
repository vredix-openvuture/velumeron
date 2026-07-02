#!/usr/bin/env python3
"""List wallpapers for one monitor — the ONE listing used by both pickers
(settings/theme/WallpaperSection.qml and osd/WallpaperQuick.qml).

Usage: wallpaper-list.py <monitor>

Output (tab-separated, subfolder first so root files carry a LEADING tab —
consumers must not trim before splitting):
    GROUP:0|1              subfolder-as-sorting active?
    <rel-subfolder>\t<absolute path>

Sorted by (subfolder, basename) when grouped, else by basename alone.
"""
import json
import os
import sys

pu = os.environ.get("VELUMERON_USER_DIR") or os.path.join(
    os.environ.get("XDG_CONFIG_HOME", "") or os.path.expanduser("~/.config"), "velumeron")
try:
    with open(os.path.join(pu, "gui", "settings.json")) as f:
        d = json.load(f)
except (OSError, ValueError):
    d = {}

mon = sys.argv[1] if len(sys.argv) > 1 else ""
vd = os.environ.get("VELUMERON_DIR", "")
dirp = ((d.get("wallpaper_dirs", {}) or {}).get(mon)
        or d.get("wallpaper_dir_hor")
        or os.path.join(vd, "assets/wallpaper/horizontal"))
dirp = os.path.expanduser(dirp)

sub = bool(d.get("wallpaper_search_subfolders"))
grouped = bool(sub and d.get("wallpaper_subfolder_sorting"))
print("GROUP:" + ("1" if grouped else "0"))

EXTS = {".png", ".jpg", ".jpeg", ".webp", ".mp4", ".webm", ".mkv", ".avi", ".mov"}
rows = []
if os.path.isdir(dirp):
    for r, _ds, fs in os.walk(dirp):
        if not sub and os.path.abspath(r) != os.path.abspath(dirp):
            continue
        rel = os.path.relpath(r, dirp)
        rel = "" if rel == "." else rel
        for f in sorted(fs):
            if os.path.splitext(f)[1].lower() in EXTS:
                rows.append((rel, os.path.join(r, f)))

if grouped:
    rows.sort(key=lambda t: (t[0].lower(), os.path.basename(t[1]).lower()))
else:
    rows.sort(key=lambda t: os.path.basename(t[1]).lower())
for rel, full in rows:
    print(rel + "\t" + full)
