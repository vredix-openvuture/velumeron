#!/usr/bin/env python3
"""List the themes installed on this machine, as JSON, for Settings -> Style.

A theme is a folder with a theme.json in it (see quickshell/Theme.qml). Two places are scanned,
user last so a user theme shadows a shipped one with the same id:

    $VELUMERON_DIR/quickshell/themes/<id>/theme.json      shipped
    $VELUMERON_USER_DIR/themes/<id>/theme.json            yours

This only READS. Making a theme of your own is theme-fork.py's job, and it only ever writes under
the user directory — a shipped theme is a folder you drop in or remove, not a record in a registry,
and the lockscreen preset registry that worked the other way is exactly what this replaced.

A theme.json that does not parse is skipped rather than failing the list, so one broken folder
cannot take the picker down with it.
"""
import json
import os
import sys


def user_dir():
    d = os.environ.get("VELUMERON_USER_DIR")
    if d:
        return d
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        return os.path.join(xdg, "velumeron")
    return os.path.join(os.path.expanduser("~"), ".config", "velumeron")


def scan(base, source, out):
    if not os.path.isdir(base):
        return
    for name in sorted(os.listdir(base)):
        path = os.path.join(base, name, "theme.json")
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8") as f:
                t = json.load(f)
        except (OSError, ValueError):
            continue
        tid = t.get("id")
        if not tid:
            continue
        arr = t.get("arrangement") or {}
        wp = t.get("wallpaper") or ""
        out[tid] = {
            "id": tid,
            "name": t.get("name", tid),
            "author": t.get("author", ""),
            "version": t.get("version", 1),
            "contract": t.get("contract", 1),
            "source": source,
            # The DESKTOP surfaces. `card` is not one of them — it is the picture the theme draws
            # of itself for the picker, and counting it would have Console announce fifteen
            # surfaces when it replaces fourteen. It travels in its own field below.
            "components": sorted(k for k in (t.get("components") or {}).keys() if k != "card"),
            "pages": len(t.get("settings") or []),
            # Parked: shipped but not built out. The picker hides these until they are finished.
            "wip": bool(t.get("wip")),
            # What the picker's preview card draws. A card is a shrunken desktop, so it needs the
            # few arrangement keys that decide the SHAPE of one — not the whole table.
            "ui_style": arr.get("ui_style", t.get("base", "flat")),
            "ui_font": arr.get("ui_font", ""),
            "bar_mode": arr.get("bar_mode", "frame"),
            "bar_position": arr.get("bar_position", "top"),
            # Absolute, because QML gets it as a file:// source. Relative in the package so the
            # folder can be moved or installed anywhere.
            "wallpaper": os.path.join(base, name, wp) if wp else "",
            # Every component the theme brings, as an absolute file path. The picker's card is a
            # WINDOW onto the desktop this theme makes, so it loads the theme's real surfaces —
            # Console's own dashboard, its own backdrop — rather than drawing an impression of
            # them. Absolute, like the wallpaper, because QML loads them as file:// sources.
            "urls": {k: os.path.join(base, name, v)
                     for k, v in (t.get("components") or {}).items() if isinstance(v, str)},
            # What the picker's card needs to look like the theme it offers rather than like the
            # one you are wearing: the table it starts from and its own overrides, resolved on the
            # QML side against the LIVE palette (Style.resolveTable).
            "base": t.get("base", arr.get("ui_style", "flat")),
            "tokens": t.get("tokens") or {},
            "bar_thickness": arr.get("bar_thickness", 36),
            "bar_inner_radius": arr.get("bar_inner_radius", 16),
            # The module treatment. The card SHOWS a module background whether or not the running
            # desk has one ("module" is the default here, not VtlConfig's "none"): the shape of a
            # module is half of what tells two themes apart from across the room, and a card that
            # hides it draws mirobo and Console as the same strip. The radius is not here at all —
            # it comes from the theme's own token table on the QML side, which is the only place
            # that knows whether this theme is round or square.
            "bar_module_bg": arr.get("bar_module_bg", "module"),
            "bar_module_bg_opacity": arr.get("bar_module_bg_opacity", 0.22),
            "bar_module_spacing": arr.get("bar_module_spacing", 10),
        }


def load(tid):
    """The full theme.json for one id, user first so a user theme shadows a shipped one."""
    vtl = os.environ.get("VELUMERON_DIR", "")
    for base in (os.path.join(user_dir(), "themes"),
                 os.path.join(vtl, "quickshell", "themes") if vtl else None):
        if not base:
            continue
        path = os.path.join(base, tid, "theme.json")
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return None
    return None


def main():
    # `arrangement <id>` prints the settings keys that theme wants applied when it is picked.
    # Everything else lists what is installed.
    if len(sys.argv) > 2 and sys.argv[1] == "arrangement":
        t = load(sys.argv[2]) or {}
        json.dump(t.get("arrangement") or {}, sys.stdout)
        sys.stdout.write("\n")
        return
    vtl = os.environ.get("VELUMERON_DIR", "")
    out = {}
    if vtl:
        scan(os.path.join(vtl, "quickshell", "themes"), "builtin", out)
    scan(os.path.join(user_dir(), "themes"), "user", out)
    json.dump(list(out.values()), sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
