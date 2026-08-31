#!/usr/bin/env python3
"""Back the desktop up to one file, and put it back.

What a backup has to carry is everything that is NOT re-derivable: the settings, the palette choice
(wallust's options and colour mode), and the themes you made yourself. Shipped themes are part of
the package, so the bundle carries only yours; which theme you wear rides along in the settings.

A restore keeps this machine's hardware-bound keys — monitor names, wallpaper folders, bluetooth
aliases — because a backup taken on another desk must not hand you its monitors.

  settings-backup.py export <path>    write a .velbak bundle
  settings-backup.py import <path>    read one back, applied live

Both print one line the settings page listens on: `export:ok:<path>`, `import:ok`, `import:invalid`.
"""

import json
import os
import sys
import tempfile

# ── Paths ────────────────────────────────────────────────────────────────────────────────────────


def _env(name, default=""):
    v = os.environ.get(name)
    return v if v else default


def user_dir():
    d = _env("VELUMERON_USER_DIR")
    if d:
        return d
    xdg = _env("XDG_CONFIG_HOME")
    base = xdg if xdg else os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "velumeron")


def settings_path():
    return os.path.join(user_dir(), "gui", "settings.json")


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


# Settings that describe THIS DEVICE / user, not a look. A restore keeps the current machine's
# values for these: a bundle from another desk carries that desk's monitors, wallpaper folders and
# bluetooth aliases, and writing them here would leave a shell talking about hardware you do not
# have. Kept in step with Theme.qml's `deviceKeys` and theme-fork.py.
DEVICE_KEYS = ("wallpaper_dirs", "bt_aliases", "bt_groups", "bar_per_monitor", "bar_monitors",
               "wallpaper_sets", "taskbar_pinned",
               # The two lock settings that are about YOU rather than about a look. `theme` is NOT
               # in this list: which theme you wear is exactly what a backup should restore.
               "lock_weather_city", "lock_weather_unit")
# A theme's own knobs (`theme_<id>_<key>`) are NOT in that list even though they look device-ish.
# They are settings you made, and a backup that hands you back the desktop without them is not a
# backup of the desktop.


def is_device_key(k):
    return k in DEVICE_KEYS


def _wallust_path(*parts):
    return os.path.join(user_dir(), "wallust", *parts)


def verb_export(path):
    import datetime
    bundle = {
        "_velumeron_export": 1,
        "exported_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "settings": read_json(settings_path(), {}),
        "user_themes": {},
    }
    wopts = read_json(_wallust_path("options.json"), None)
    if isinstance(wopts, dict):
        bundle["wallust_options"] = wopts
    cm = _wallust_path("color-mode")
    if os.path.isfile(cm):
        try:
            bundle["color_mode"] = open(cm, encoding="utf-8").read().strip()
        except OSError:
            pass
    themes = os.path.join(user_dir(), "themes")
    if os.path.isdir(themes):
        for theme_id in sorted(os.listdir(themes)):
            theme = read_json(os.path.join(themes, theme_id, "theme.json"), None)
            if isinstance(theme, dict):
                bundle["user_themes"][theme_id] = theme

    path = os.path.abspath(os.path.expanduser(path))
    if not os.path.splitext(path)[1]:
        path += ".velbak"          # the bundle is JSON, but it is OUR bundle — give it our suffix
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(bundle, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("export:ok:%s" % path)


def verb_import(path):
    path = os.path.abspath(os.path.expanduser(path))
    data = read_json(path, None)
    if not isinstance(data, dict) or not data.get("_velumeron_export"):
        # stdout, not stderr: this line is the protocol the settings page listens on (it only
        # reads stdout), so on stderr the "not a backup file" message never reached the user.
        print("import:invalid")
        sys.exit(1)

    new_settings = data.get("settings")
    if isinstance(new_settings, dict):
        cur = read_json(settings_path(), {})
        for k in cur:                    # keep this device's hardware-bound keys
            if is_device_key(k):
                new_settings[k] = cur[k]
        write_settings(new_settings)

    if isinstance(data.get("wallust_options"), dict):
        write_json(_wallust_path("options.json"), data["wallust_options"])
    if isinstance(data.get("color_mode"), str):
        os.makedirs(_wallust_path(), exist_ok=True)
        with open(_wallust_path("color-mode"), "w", encoding="utf-8") as f:
            f.write(data["color_mode"] + "\n")

    # A user theme is a folder; the bundle carries its theme.json, which is the only file in it
    # that cannot be re-derived. Anything else the theme shipped (its components) came from the
    # package it was forked from and is still installed.
    for theme_id, theme in (data.get("user_themes") or {}).items():
        if isinstance(theme, dict) and "/" not in theme_id and theme_id not in ("", ".", ".."):
            write_json(os.path.join(user_dir(), "themes", theme_id, "theme.json"), theme)

    print("import:ok")


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: settings-backup <export|import> <path>", file=sys.stderr)
        sys.exit(2)
    verb, rest = args[0], args[1:]
    dispatch = {
        "export": lambda: verb_export(rest[0]),
        "import": lambda: verb_import(rest[0]),
    }
    fn = dispatch.get(verb)
    if not fn:
        print("unknown verb: %s" % verb, file=sys.stderr)
        sys.exit(2)
    fn()


if __name__ == "__main__":
    main()
