#!/usr/bin/env bash
# icon-theme-preview.sh <icon-theme-name>
# Prints absolute file paths (one per line) for a handful of representative icons
# resolved WITHIN the given icon theme (following its Inherits= chain), so the
# settings UI can preview a theme's look. Best-effort: prints only what it resolves.
set -euo pipefail
theme="${1:-}"
[ -n "$theme" ] || { echo "usage: icon-theme-preview.sh <theme>" >&2; exit 2; }

python3 - "$theme" <<'PY'
import os, sys, glob, configparser

theme = sys.argv[1]
bases = [os.path.expanduser("~/.icons"),
         os.path.expanduser("~/.local/share/icons"),
         "/usr/share/icons"]

def theme_dir(name):
    for b in bases:
        d = os.path.join(b, name)
        if os.path.isdir(d):
            return d
    return None

def inherits(name):
    d = theme_dir(name)
    if not d:
        return []
    c = configparser.RawConfigParser(); c.optionxform = str
    try:
        c.read(os.path.join(d, "index.theme"))
    except Exception:
        return []
    if c.has_option("Icon Theme", "Inherits"):
        return [x.strip() for x in c.get("Icon Theme", "Inherits").split(",") if x.strip()]
    return []

# Search chain: the theme + everything it inherits (breadth-first, de-duped), hicolor last.
chain, seen, stack = [], set(), [theme]
while stack:
    n = stack.pop(0)
    if n in seen:
        continue
    seen.add(n); chain.append(n)
    stack.extend(inherits(n))
if "hicolor" not in seen:
    chain.append("hicolor")

# Representative, near-universal freedesktop names; first five that resolve win.
wanted = ["folder", "user-home", "web-browser", "utilities-terminal",
          "text-editor", "system-file-manager", "applications-system", "preferences-system"]

def size_score(p):
    for s in ("48", "64", "32", "96", "128", "256", "24", "22", "16"):
        if "/%s/" % s in p or "/%sx%s/" % (s, s) in p:
            return abs(48 - int(s))
    return 999  # scalable / unknown → neutral

def find_icon(name):
    for tname in chain:
        d = theme_dir(tname)
        if not d:
            continue
        cands = []
        for ext in (".png", ".svg"):
            cands += glob.glob(os.path.join(d, "*", "*", name + ext))
            cands += glob.glob(os.path.join(d, "*", name + ext))
        if cands:
            cands.sort(key=size_score)
            return cands[0]
    return None

out = []
for name in wanted:
    p = find_icon(name)
    if p:
        out.append(p)
    if len(out) >= 5:
        break
for p in out:
    print(p)
PY
