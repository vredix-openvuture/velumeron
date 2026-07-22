#!/usr/bin/env python3
"""cursor-build.py — compile the `velumeron-dynamic` cursor theme from the live
wallust palette.

Recolours the vendored Bibata SVGs (cursors/velumeron-dynamic/) and builds BOTH:

  • Hyprcursor  (SVG, scalable)  — native Wayland apps, via hyprcursor-util
  • Xcursor     (PNG, per-size)  — XWayland / X11 apps, via the pure-python encoder

…into ~/.local/share/icons/velumeron-dynamic/, so the pointer follows the
wallpaper like every other themed tool.

Design: the cursor BODY stays white and only the OUTLINE carries the wallust
accent (luminance-clamped for contrast), so it stays readable on any wallpaper —
a fully accent-filled cursor vanishes on a similar background.

Usage:
    cursor-build.py                build from the current palette
    cursor-build.py --if-selected  build only if velumeron-dynamic is the active
                                    cursor theme (the wallust-hook entry point)
"""
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from xcursor_encode import write_xcursor

HOME = Path.home()
CFG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache"))
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))

THEME = "velumeron-dynamic"
# Resolve the repo tree through the ~/.config/velumeron/assets/scripts symlink.
VELUMERON_DIR = Path(os.environ.get(
    "VELUMERON_DIR", Path(__file__).resolve().parent.parent.parent))
SRC = VELUMERON_DIR / "cursors" / THEME
INSTALL = DATA / "icons" / THEME

# Xcursor is raster, so it needs concrete sizes. Cover the common HiDPI ladder;
# animated shapes use a lighter ladder (frames × sizes is the costly axis).
SIZES = [24, 32, 48, 64]
ANIM_SIZES = [24, 32, 48]

# Bibata placeholder colours (see cursors/velumeron-dynamic/README.md).
BODY_PH = "#00FF00"
OUTLINE_PH = "#0000FF"
DETAIL_PH = "#FF0000"
SPINNER_PH = ["#FCB813", "#7EBA41", "#32A0DA", "#F05024"]  # light → dark trail

FALLBACK = {"color0": "#040702", "color3": "#A49E76", "color5": "#BA6132"}


# ── colour helpers ──────────────────────────────────────────────────────────
def _rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _hex(rgb):
    return "#" + "".join(f"{max(0, min(255, round(c))):02x}" for c in rgb)


def _mix(a, b, t):
    ra, rb = _rgb(a), _rgb(b)
    return _hex(tuple(ra[i] + (rb[i] - ra[i]) * t for i in range(3)))


def load_palette():
    for p in (CFG / "velumeron/quickshell/colors.json",
              CACHE / "wallust/colors.json"):
        try:
            d = json.loads(p.read_text())
            if isinstance(d.get("color0"), str):
                return d
        except (OSError, ValueError):
            continue
    return dict(FALLBACK)


# Body = bar background blended part-way toward the bar accent: dark, but with a
# gentle wash of colour. 0 = pure dark bar bg, 1 = full accent. Tune to taste.
BODY_ACCENT_MIX = 0.5
# Damp the border toward the body so the edge isn't too poppy. 0 = full bar
# border colour, higher = more muted / closer to the body.
BORDER_DAMP = 0.45
# Lift the body toward neutral grey — brighter/more visible without adding
# saturation. 0 = no lift, higher = lighter and greyer.
BODY_LIGHTEN = 0.22
BODY_NEUTRAL = "#CCCCCC"


def build_palette(pal):
    """Map the 7 placeholders so the cursor harmonises with the BAR:

      body    = bar background nudged toward the accent (dark, subtly tinted —
                between bgPrimary/color0 and bgActive/color3)
      outline = the bar border      (Style.chromeBorder = boNormal/color5 in the
                flat/default variants — the accent line around the bar)

    A dark, lightly-coloured body with the bar's own border colour, so the
    pointer reads as part of the same material as the bar."""
    c0 = pal.get("color0", FALLBACK["color0"])      # bgPrimary — bar fill
    c3 = pal.get("color3", FALLBACK["color3"])      # bgActive  — bar accent
    body = _mix(c0, c3, BODY_ACCENT_MIX)
    body = _mix(body, BODY_NEUTRAL, BODY_LIGHTEN)   # lift toward neutral grey
    # boNormal/color5 is the bar border; damp it toward the body so it's less poppy.
    border = _mix(pal.get("color5", FALLBACK["color5"]), body, BORDER_DAMP)
    return {
        BODY_PH: body,               # body: bar accent colour
        OUTLINE_PH: border,          # outline: bar border colour
        DETAIL_PH: _mix(body, "#000000", 0.45),  # detail: darker than body
        # wait-spinner comet trail, light → bar-border accent
        SPINNER_PH[0]: _mix(border, "#FFFFFF", 0.55),
        SPINNER_PH[1]: _mix(border, "#FFFFFF", 0.30),
        SPINNER_PH[2]: _mix(border, "#FFFFFF", 0.10),
        SPINNER_PH[3]: border,
    }


def make_recolour(palette):
    # One case-insensitive pass over the known placeholders.
    pat = re.compile("|".join(re.escape(k) for k in palette), re.IGNORECASE)
    upper = {k.upper(): v for k, v in palette.items()}
    return lambda svg: pat.sub(lambda m: upper[m.group(0).upper()], svg)


# ── rendering ───────────────────────────────────────────────────────────────
def render_bgra(svg_bytes, size):
    """SVG bytes → premultiplied BGRA bytes at size×size (for Xcursor)."""
    png = subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size)],
        input=svg_bytes, stdout=subprocess.PIPE, check=True).stdout
    img = Image.open(io.BytesIO(png)).convert("RGBA")
    if img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    arr = np.asarray(img, dtype=np.uint16)          # H×W×4 RGBA, straight alpha
    a = arr[..., 3:4]
    rgb = (arr[..., :3] * a + 127) // 255            # premultiply
    out = np.empty(arr.shape, dtype=np.uint8)
    out[..., 0] = rgb[..., 2]                        # B
    out[..., 1] = rgb[..., 1]                        # G
    out[..., 2] = rgb[..., 0]                        # R
    out[..., 3] = arr[..., 3]                        # A
    return out.tobytes()


# ── build ───────────────────────────────────────────────────────────────────
def build():
    meta = json.loads((SRC / "meta.json").read_text())
    canvas = meta["canvas"]
    pal = load_palette()
    colours = build_palette(pal)
    recolour = make_recolour(colours)

    staging = Path(tempfile.mkdtemp(prefix="velumeron-cursor-"))
    hypr_src = staging / "hypr_src"
    (hypr_src / "hyprcursors").mkdir(parents=True)
    xcur_dir = staging / "cursors"
    xcur_dir.mkdir()

    (hypr_src / "manifest.hl").write_text(
        f"name = {THEME}\n"
        "description = Velumeron wallust-following cursor\n"
        "version = 1.0\n"
        "cursors_directory = hyprcursors\n")

    # Recolour every shape's SVG(s) once; reuse for both back-ends.
    render_jobs = []   # (out_path, svg_bytes, size, xhot, yhot, delay, name, sizekey)
    for c in meta["cursors"]:
        name = c["name"]
        hx, hy = c["hotspot"]
        shape_dir = hypr_src / "hyprcursors" / name
        shape_dir.mkdir()
        lines = ["resize_algorithm = bilinear",
                 f"hotspot_x = {hx / canvas:.4f}",
                 f"hotspot_y = {hy / canvas:.4f}"]

        if "frames" in c:
            frames = c["frames"]
            delay = c.get("delay", 40)
            svgs = []
            for i, fn in enumerate(frames):
                svg = recolour((SRC / "svg" / name / fn).read_text())
                out = f"frame-{i:03d}.svg"
                (shape_dir / out).write_text(svg)
                lines.append(f"define_size = 0, {out}, {delay}")
                svgs.append(svg.encode())
            sizes = ANIM_SIZES
        else:
            svg = recolour((SRC / "svg" / c["svg"]).read_text())
            (shape_dir / f"{name}.svg").write_text(svg)
            lines.append(f"define_size = 0, {name}.svg")
            svgs = [svg.encode()]
            delay = 0
            sizes = SIZES

        for alias in c["symlinks"]:
            lines.append(f"define_override = {alias}")
        (shape_dir / "meta.hl").write_text("\n".join(lines) + "\n")

        # Queue Xcursor renders (one per size per frame).
        xjobs = []
        for size in sizes:
            xhot = round(hx / canvas * size)
            yhot = round(hy / canvas * size)
            for fi, sb in enumerate(svgs):
                xjobs.append((size, xhot, yhot, delay, fi, sb))
        render_jobs.append((name, c["symlinks"], xjobs))

    # ── Hyprcursor: compile the whole source tree in one go ──
    subprocess.run(["hyprcursor-util", "--create", str(hypr_src),
                    "--output", str(staging)],
                   check=True, stdout=subprocess.DEVNULL)
    built = staging / f"theme_{THEME}"

    # ── Xcursor: render in parallel, then encode each shape ──
    def render_one(job):
        size, xhot, yhot, delay, fi, sb = job
        return (size, xhot, yhot, delay, fi, render_bgra(sb, size))

    with ThreadPoolExecutor(max_workers=(os.cpu_count() or 4)) as pool:
        for name, symlinks, xjobs in render_jobs:
            results = list(pool.map(render_one, xjobs))
            images = []
            for size, xhot, yhot, delay, fi, px in results:
                images.append({"size": size, "width": size, "height": size,
                               "xhot": xhot, "yhot": yhot, "delay": delay,
                               "pixels": px})
            write_xcursor(xcur_dir / name, images)
            for alias in symlinks:
                link = xcur_dir / alias
                if not link.exists():
                    link.symlink_to(name)

    (staging / "index.theme").write_text(
        "[Icon Theme]\n"
        f"Name={THEME}\n"
        "Comment=Velumeron wallust-following cursor\n"
        "Inherits=Adwaita\n")

    # ── Atomic install ──
    INSTALL.parent.mkdir(parents=True, exist_ok=True)
    tmp_install = INSTALL.with_name(f".{THEME}.new")
    if tmp_install.exists():
        shutil.rmtree(tmp_install)
    tmp_install.mkdir()
    shutil.copytree(xcur_dir, tmp_install / "cursors", symlinks=True)
    shutil.copytree(built / "hyprcursors", tmp_install / "hyprcursors")
    shutil.copyfile(built / "manifest.hl", tmp_install / "manifest.hl")
    shutil.copyfile(staging / "index.theme", tmp_install / "index.theme")

    # Swap via two renames (old aside, new in) instead of rmtree+rename, so the
    # theme dir is never missing for the whole delete — only for two syscalls.
    if INSTALL.exists():
        old = INSTALL.with_name(f".{THEME}.old")
        if old.exists():
            shutil.rmtree(old)
        INSTALL.rename(old)
        tmp_install.rename(INSTALL)
        shutil.rmtree(old, ignore_errors=True)
    else:
        tmp_install.rename(INSTALL)
    shutil.rmtree(staging, ignore_errors=True)
    return colours[BODY_PH], colours[OUTLINE_PH]


def _user_settings():
    us = CFG / "velumeron/hypr.lua/user_settings.lua"
    if not us.exists():
        us = VELUMERON_DIR / "hypr.lua" / "user_settings.lua"
    try:
        return us.read_text()
    except OSError:
        return ""


def is_selected():
    """True if velumeron-dynamic is the active cursor theme in user_settings."""
    m = re.search(r'cur_theme\s*=\s*"([^"]*)"', _user_settings())
    return bool(m and m.group(1) == THEME)


def refresh_live():
    """Re-apply the freshly-built theme so the ON-SCREEN cursor updates now.

    Hyprland caches a loaded hyprcursor theme by NAME for the whole session:
    once `velumeron-dynamic` is loaded, `setcursor velumeron-dynamic` reuses the
    cached (old-colour) textures even after the files on disk change. So each
    rebuild is published under a fresh, never-seen name — a throwaway copy of the
    theme with a unique `name` in its manifest — and we point Hyprland at that.
    A name it has never loaded forces a real fresh load (exactly like a manual
    theme switch), so the new colours actually appear. Old generations are pruned.

    The stable `velumeron-dynamic` dir stays updated too — that is what the
    HYPRCURSOR/XCURSOR env vars, XWayland and the next login resolve."""
    m = re.search(r'cur_size\s*=\s*(\d+)', _user_settings())
    size = m.group(1) if m else "24"
    icons = INSTALL.parent
    gen = int(time.time())
    live_name = f"{THEME}-live{gen}"
    live_dir = icons / live_name
    if live_dir.exists():
        shutil.rmtree(live_dir, ignore_errors=True)
    shutil.copytree(INSTALL, live_dir, symlinks=True)
    # Rename the theme inside the manifest/index so hyprcursor keys its cache on
    # the unique name (it uses the manifest name, not just the directory).
    mani = live_dir / "manifest.hl"
    mani.write_text(re.sub(r'(?m)^name\s*=.*$', f'name = {live_name}',
                           mani.read_text(), count=1))
    idx = live_dir / "index.theme"
    if idx.exists():
        idx.write_text(re.sub(r'(?m)^Name=.*$', f'Name={live_name}',
                              idx.read_text(), count=1))
    subprocess.run(
        ["bash", "-c",
         f'hyprctl setcursor {live_name} {size} >/dev/null 2>&1; '
         'p=$(hyprctl cursorpos 2>/dev/null); x=${p%,*}; y=${p#*, }; '
         '[ -n "$x" ] && hyprctl dispatch "hl.dsp.cursor.move({x=$x, y=$y})" '
         '>/dev/null 2>&1'],
        check=False)
    # Prune older live generations.
    for p in icons.glob(f"{THEME}-live*"):
        if p.name != live_name:
            shutil.rmtree(p, ignore_errors=True)


def main():
    selected = is_selected()
    if "--if-selected" in sys.argv and not selected:
        return 0
    body, border = build()
    print(f"built {THEME} (body {body}, border {border}) → {INSTALL}")
    if selected:
        refresh_live()
    return 0


if __name__ == "__main__":
    sys.exit(main())
