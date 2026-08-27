#!/usr/bin/env python3
"""Backend for the lockscreen preset system (mirror of velumeron-config.py, scoped to the lock).

A lock preset is a small JSON: { id, name, author, builtin, version, settings: { <lock_* keys> } }.
Builtins ship read-only under $VELUMERON_DIR/assets/lockscreen/presets/, user presets are writable
under $VELUMERON_USER_DIR/lockscreens/, and the active pointer lives in
$VELUMERON_USER_DIR/active-lockscreen.json. "Applying" a preset merges only its lock_* keys into
gui/settings.json (atomically), so the live shell (VtlConfig FileView) recolours the lock at once.

Verbs:
  list                          → {"presets":[...], "activeId":..., "activeSource":...}
  activate <source> <id>        → merge preset's settings into settings.json + set active marker
  save <name> <settings-json>   → write a user preset from the given lock settings, then activate it
  duplicate <source> <id> <name>→ copy a preset into a new user preset
  rename <id> <name>            → rename a user preset (id/file kept)
  delete <id>                   → remove a user preset (falls back to console if it was active)
  init                          → ensure an active marker exists, and move a session still pointing
                                  at one of the parked builtins onto the shipped one
"""
import glob
import json
import os
import re
import sys
import tempfile

VD = os.environ.get("VELUMERON_DIR", "")
UD = os.environ.get("VELUMERON_USER_DIR") or os.path.expanduser("~/.config/velumeron")
BUILTIN_DIR = os.path.join(VD, "assets/lockscreen/presets")
USER_DIR = os.path.join(UD, "lockscreens")
SETTINGS = os.path.join(UD, "gui/settings.json")
MARKER = os.path.join(UD, "active-lockscreen.json")

# The lock keys a preset owns — must stay in sync with VtlConfig.lockKeys.
LOCK_KEYS = [
    "lock_layout",
    "lock_reveal", "lock_blur", "lock_dim", "lock_card_wallpaper", "lock_card_avatar",
    "lock_uniform_wallpaper", "lock_widget_zones",
    "lock_card_pos", "lock_card_width_pct", "lock_card_height_pct",
    "lock_weather_city", "lock_weather_unit", "lock_weather_forecast",
    "lock_weather_forecast_days", "lock_clock_format", "lock_date_format",
    "lock_clock_scale", "lock_clock_style", "lock_blur_target",
]


def slug(name):
    s = re.sub(r"[^a-z0-9]+", "-", (name or "").strip().lower()).strip("-")
    return s or "preset"


def read_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def atomic_write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp.")
    with os.fdopen(fd, "w") as f:
        json.dump(obj, f, indent=1)
    os.replace(tmp, path)


# The six presets that shipped until 2026-08-27 and now sit in presets/_parked/. `init` moves a
# marker still pointing at one of them onto DEFAULT_PRESET: the file it names is no longer scanned,
# so leaving the pointer would show Settings an active preset that is not in its own list.
PARKED_BUILTINS = {"vitrine", "mirobo", "console-hud", "diptych", "focus", "marginalia"}
DEFAULT_PRESET = "console"


def _on_old_console(aid):
    """Was this session on the OLD Console — the hairline HUD that carried the same id?

    The parked file was renamed to console-hud.json, but the marker a user already has on disk
    says "console", which now resolves to the new preset. Without this the settings page would
    report Console active over a lock still drawing the hairline frame. The layout is the tell:
    nothing but the old preset puts `console` and `hud` together.
    """
    if aid != DEFAULT_PRESET:
        return False
    return (read_json(SETTINGS, {}) or {}).get("lock_layout") == "hud"


def active():
    m = read_json(MARKER, {}) or {}
    return m.get("id", DEFAULT_PRESET), m.get("source", "builtin")


def set_active(pid, source):
    atomic_write(MARKER, {"id": pid, "source": source})


def find(source, pid):
    d = BUILTIN_DIR if source == "builtin" else USER_DIR
    for f in glob.glob(os.path.join(d, "*.json")):
        p = read_json(f)
        if p and (p.get("id") == pid or os.path.splitext(os.path.basename(f))[0] == pid):
            return f, p
    return None, None


def apply_settings(settings, pid):
    s = read_json(SETTINGS, {}) or {}
    for k in LOCK_KEYS:
        if k in settings:
            s[k] = settings[k]
    s["lock_preset"] = pid
    atomic_write(SETTINGS, s)


def scan():
    aid, asrc = active()
    out = []
    for src, d in (("builtin", BUILTIN_DIR), ("user", USER_DIR)):
        for f in sorted(glob.glob(os.path.join(d, "*.json"))):
            p = read_json(f)
            if not p:
                continue
            pid = p.get("id") or os.path.splitext(os.path.basename(f))[0]
            out.append({
                "id": pid,
                "name": p.get("name", pid),
                "author": p.get("author", ""),
                "builtin": bool(p.get("builtin", src == "builtin")),
                "source": src,
                "active": (pid == aid and src == asrc),
                "settings": p.get("settings", {}),
            })
    return out, aid, asrc


def main():
    verb = sys.argv[1] if len(sys.argv) > 1 else "list"

    if verb == "list":
        items, aid, asrc = scan()
        print(json.dumps({"presets": items, "activeId": aid, "activeSource": asrc}))

    elif verb == "activate":
        source, pid = sys.argv[2], sys.argv[3]
        _, p = find(source, pid)
        if not p:
            sys.exit(1)
        apply_settings(p.get("settings", {}), pid)
        set_active(pid, source)

    elif verb == "save":
        name = sys.argv[2]
        settings = json.loads(sys.argv[3])
        pid = slug(name)
        preset = {
            "id": pid, "name": name, "author": "", "builtin": False, "version": 1,
            "settings": {k: settings[k] for k in LOCK_KEYS if k in settings},
        }
        atomic_write(os.path.join(USER_DIR, pid + ".json"), preset)
        apply_settings(preset["settings"], pid)
        set_active(pid, "user")
        print(pid)

    elif verb == "duplicate":
        source, pid, name = sys.argv[2], sys.argv[3], sys.argv[4]
        _, p = find(source, pid)
        if not p:
            sys.exit(1)
        nid = slug(name)
        preset = {
            "id": nid, "name": name, "author": "", "builtin": False, "version": 1,
            "settings": p.get("settings", {}),
        }
        atomic_write(os.path.join(USER_DIR, nid + ".json"), preset)
        print(nid)

    elif verb == "rename":
        pid, name = sys.argv[2], sys.argv[3]
        f, p = find("user", pid)
        if not p:
            sys.exit(1)
        p["name"] = name
        atomic_write(f, p)

    elif verb == "delete":
        pid = sys.argv[2]
        f, _ = find("user", pid)
        if f:
            os.remove(f)
        aid, asrc = active()
        if aid == pid and asrc == "user":
            _, mp = find("builtin", DEFAULT_PRESET)
            if mp:
                apply_settings(mp.get("settings", {}), DEFAULT_PRESET)
            set_active(DEFAULT_PRESET, "builtin")

    elif verb == "init":
        aid, asrc = active()
        if not os.path.exists(MARKER):
            set_active(DEFAULT_PRESET, "builtin")
        elif asrc == "builtin" and (aid in PARKED_BUILTINS or _on_old_console(aid)):
            # A session still on one of the parked builtins gets the shipped one applied, not just
            # pointed at: leaving the keys alone would show Settings "Console, active" over a lock
            # that still draws Vitrine. The preset carries no weather city, so the one setting
            # nobody wants re-typed survives. A preset the user SAVED (source "user") is never
            # touched by this.
            _, np = find("builtin", DEFAULT_PRESET)
            if np:
                apply_settings(np.get("settings", {}), DEFAULT_PRESET)
            set_active(DEFAULT_PRESET, "builtin")


if __name__ == "__main__":
    main()
