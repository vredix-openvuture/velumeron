#!/usr/bin/env python3
"""List the themes installed on this machine, as JSON, for Settings -> Style.

A theme is a folder with a theme.json in it (see quickshell/Theme.qml). Two places are scanned,
user last so a user theme shadows a shipped one with the same id:

    $VELUMERON_DIR/quickshell/themes/<id>/theme.json      shipped
    $VELUMERON_USER_DIR/themes/<id>/theme.json            yours

This only READS. There is deliberately no save/duplicate/delete verb: a theme is a folder you drop
in or remove, not a record in a registry, and the lockscreen preset registry that worked the other
way is exactly what this replaced.

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
        out[tid] = {
            "id": tid,
            "name": t.get("name", tid),
            "author": t.get("author", ""),
            "version": t.get("version", 1),
            "contract": t.get("contract", 1),
            "source": source,
            "components": sorted((t.get("components") or {}).keys()),
            "pages": len(t.get("settings") or []),
        }


def main():
    vtl = os.environ.get("VELUMERON_DIR", "")
    out = {}
    if vtl:
        scan(os.path.join(vtl, "quickshell", "themes"), "builtin", out)
    scan(os.path.join(user_dir(), "themes"), "user", out)
    json.dump(list(out.values()), sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
