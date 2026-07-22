#!/usr/bin/env python3
"""Compute a wallust palette for CANDIDATE options WITHOUT touching the live theme.

Settings → Style → Colours shows a little preview of what your colours look like. When you change a
wallust option (palette / backend / colorspace / vividness) this script lets that preview show the
RESULT before you commit it with "Apply": it runs wallust with the given options on the current
wallpaper into a throwaway config-dir — a single template rendering the flat colours JSON to a temp
file, NO [hooks], and -s (skip terminal sequences) — so nothing about the live desktop changes. The
resulting {background, foreground, color0..15} JSON is printed to stdout for the shell to parse.

Usage:
  preview-palette.py <palette> <backend> <colorspace> <saturation> <check_contrast 0|1> [wallpaper]

Empty option args are skipped (wallust falls back to its config defaults). Exit non-zero (no stdout)
when there is no usable image — the caller then just keeps showing the live palette.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile


def _env(name, default=""):
    v = os.environ.get(name)
    return v if v else default


def repo_dir():
    d = _env("VELUMERON_DIR")
    if d:
        return d
    # assets/scripts/lib/preview-palette.py -> repo root
    return os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", ".."))


def user_dir():
    d = _env("VELUMERON_USER_DIR")
    if d:
        return d
    xdg = _env("XDG_CONFIG_HOME")
    base = xdg if xdg else os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "velumeron")


def current_wallpaper():
    """The wallpaper wallust derives the live palette from — the first image entry in
    wallpapers.json, matching apply-theme.sh's `next(iter(...))` so the preview matches Apply."""
    p = os.path.join(user_dir(), "quickshell", "wallpapers.json")
    try:
        data = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        return ""
    # Prefer an explicit image; then any entry that resolves to a real file (type may be missing).
    for want_image in (True, False):
        for v in data.values():
            if not isinstance(v, dict):
                continue
            path = v.get("path", "")
            if want_image and v.get("type", "image") != "image":
                continue
            if path and os.path.isfile(path):
                return path
    return ""


def _run(cmd):
    try:
        r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=25)
        return r.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def main():
    a = sys.argv[1:]
    palette    = a[0] if len(a) > 0 else ""
    backend    = a[1] if len(a) > 1 else ""
    colorspace = a[2] if len(a) > 2 else ""
    saturation = a[3] if len(a) > 3 else ""
    check      = a[4] if len(a) > 4 else "0"
    wp         = (a[5] if len(a) > 5 and a[5] else "") or current_wallpaper()
    if not wp or not os.path.isfile(wp):
        return 1

    tpl_src = os.path.join(repo_dir(), "wallust", "templates", "colors.json")
    if not os.path.isfile(tpl_src):
        return 1

    tmp = tempfile.mkdtemp(prefix="vtl-cpreview-")
    try:
        os.makedirs(os.path.join(tmp, "templates"))
        shutil.copy(tpl_src, os.path.join(tmp, "templates", "colors.json"))
        out_json = os.path.join(tmp, "out.json")
        # Minimal config: one template -> temp file, no [hooks]. Global defaults are overridden by
        # the CLI flags below when set.
        toml = (
            'backend = "wal"\n'
            'color_space = "lab"\n'
            'palette = "saliencedarkdistributed"\n'
            "[templates]\n"
            "preview = { src = 'colors.json', dst = %s }\n" % json.dumps(out_json)
        )
        with open(os.path.join(tmp, "wallust.toml"), "w", encoding="utf-8") as f:
            f.write(toml)

        def build(force_backend=None):
            c = ["wallust", "--config-dir", tmp, "run", wp, "-s", "-q"]
            if palette:
                c += ["-p", palette]
            if force_backend:
                c += ["-b", force_backend]
            elif backend:
                c += ["-b", backend]
            if colorspace:
                c += ["-c", colorspace]
            try:
                if saturation and int(saturation) > 0:
                    c += ["--saturation", str(int(saturation))]
            except ValueError:
                pass
            if str(check) in ("1", "true", "True"):
                c += ["-k"]
            return c

        ok = _run(build())
        if not ok or not os.path.isfile(out_json):
            # The `wal` backend refuses near-monochrome images — retry with the robust `resized`
            # one so the preview still lands (mirrors wallpaper-set.sh's fallback).
            _run(build(force_backend="resized"))
        if not os.path.isfile(out_json):
            return 1
        sys.stdout.write(open(out_json, encoding="utf-8").read())
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
