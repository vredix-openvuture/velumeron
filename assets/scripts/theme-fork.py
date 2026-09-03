#!/usr/bin/env python3
"""Make, rename and delete a theme of your own. Writes only under $VELUMERON_USER_DIR/themes.

Shipped themes are folders you drop in or remove; nothing here ever touches them. What this adds is
the one move the picker needs and a folder cannot do by itself: fork the theme you are running into
one that is yours, carrying the settings you have actually made.

    theme-fork.py fork   <id> [name]    copy <id> to a new user theme, arrangement = your settings
    theme-fork.py rename <id> <name>    rename a user theme
    theme-fork.py delete <id>           delete a user theme

Every verb prints one line: `fork:<newid>`, `rename:ok`, `delete:ok`, or `<verb>:<reason>` on
failure. The settings page reads that line.
"""
import json
import os
import re
import shutil
import sys


def user_dir():
    d = os.environ.get("VELUMERON_USER_DIR")
    if d:
        return d
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        return os.path.join(xdg, "velumeron")
    return os.path.join(os.path.expanduser("~"), ".config", "velumeron")


def user_themes():
    return os.path.join(user_dir(), "themes")


def shipped_themes():
    return os.path.join(os.environ.get("VELUMERON_DIR", ""), "quickshell", "themes")


def package_dir(theme_id):
    """Where <theme_id> lives, yours first — the same order Theme.qml resolves in."""
    for base in (user_themes(), shipped_themes()):
        path = os.path.join(base, theme_id)
        if os.path.isfile(os.path.join(path, "theme.json")):
            return path
    return ""


def hypr_look(theme_id):
    """The Hyprland look for <theme_id>, yours first — the same order hyprland.lua dofiles in."""
    for base in (os.path.join(user_dir(), "hypr.lua", "themes"),
                 os.path.join(os.environ.get("VELUMERON_DIR", ""), "hypr.lua", "themes")):
        path = os.path.join(base, theme_id + ".lua")
        if os.path.isfile(path):
            return path
    return ""


def user_hypr_look(theme_id):
    return os.path.join(user_dir(), "hypr.lua", "themes", theme_id + ".lua")


def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_theme(path, theme):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(theme, f, indent=2, ensure_ascii=False)
        f.write("\n")


def slugify(name):
    slug = re.sub(r"[^a-z0-9]+", "-", ("" + name).strip().lower()).strip("-")
    return slug or "theme"


def free_id(base):
    root = user_themes()
    theme_id, n = base, 2
    while os.path.exists(os.path.join(root, theme_id)):
        theme_id = "%s-%d" % (base, n)
        n += 1
    return theme_id


# A theme never carries what belongs to the machine: monitor names, wallpaper folders, bluetooth
# aliases, which theme is worn. Kept in step with Theme.qml's `deviceKeys` and settings-backup.py.
DEVICE_KEYS = ("theme", "wallpaper_dirs", "wallpaper_sets", "bt_aliases", "bt_groups",
               "bar_per_monitor", "bar_monitors", "taskbar_pinned",
               "lock_weather_city", "lock_weather_coords", "lock_weather_unit")


def fail(verb, reason):
    print("%s:%s" % (verb, reason))
    sys.exit(1)


def verb_fork(source_id, name=""):
    """A fork keeps the source's look and takes YOUR arrangement.

    The point of forking is "I like this theme but I have moved the bar and changed the font" — so
    the copy inherits tokens, components and lock unchanged, and its arrangement is the source's
    key list read out of the live settings.json. Keys the source never claimed stay unclaimed, or
    picking the fork would start writing settings its parent has no opinion about.
    """
    src = package_dir(source_id)
    if not src:
        fail("fork", "notfound")
    theme = read_json(os.path.join(src, "theme.json"), None)
    if theme is None:
        fail("fork", "unreadable")

    new_id = free_id(slugify(name)) if name.strip() else free_id(source_id + "-mine")
    dst = os.path.join(user_themes(), new_id)
    shutil.copytree(src, dst)

    settings = read_json(os.path.join(user_dir(), "gui", "settings.json"), {})
    arrangement = {k: settings.get(k, v) for k, v in (theme.get("arrangement") or {}).items()
                   if k not in DEVICE_KEYS and not k.startswith("theme_")}

    theme["id"] = new_id
    theme["name"] = name.strip() if name.strip() else (theme.get("name", source_id) + " (yours)")
    theme["author"] = "you"
    theme["arrangement"] = arrangement
    theme.pop("wip", None)                   # a fork is something you use, never a parked preview
    write_theme(os.path.join(dst, "theme.json"), theme)

    # The window frames follow the theme too, and hyprland.lua looks that look up BY ID — a fork
    # without one of its own would quietly fall back to the base frame while everything else about
    # it stayed the parent's.
    look = hypr_look(source_id)
    if look:
        os.makedirs(os.path.dirname(user_hypr_look(new_id)), exist_ok=True)
        shutil.copyfile(look, user_hypr_look(new_id))
    print("fork:%s" % new_id)


def verb_rename(theme_id, name):
    path = os.path.join(user_themes(), theme_id, "theme.json")
    if not os.path.isfile(path):
        fail("rename", "notyours")
    theme = read_json(path, None)
    if theme is None:
        fail("rename", "unreadable")
    theme["name"] = name.strip() or theme.get("name", theme_id)
    write_theme(path, theme)
    print("rename:ok")


def verb_delete(theme_id):
    path = os.path.join(user_themes(), theme_id)
    if not os.path.isfile(os.path.join(path, "theme.json")):
        fail("delete", "notyours")
    shutil.rmtree(path)
    look = user_hypr_look(theme_id)          # the fork's window frames go with it
    if os.path.isfile(look):
        os.remove(look)
    print("delete:ok")


def main():
    args = sys.argv[1:]
    if not args:
        fail("theme-fork", "noverb")
    verb = args[0]
    if verb == "fork" and len(args) >= 2:
        verb_fork(args[1], args[2] if len(args) > 2 else "")
    elif verb == "rename" and len(args) >= 3:
        verb_rename(args[1], args[2])
    elif verb == "delete" and len(args) >= 2:
        verb_delete(args[1])
    else:
        fail("theme-fork", "badargs")


if __name__ == "__main__":
    main()
