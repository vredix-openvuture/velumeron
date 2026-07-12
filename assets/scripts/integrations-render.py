#!/usr/bin/env python3
"""Velumeron integrations — palette renderer.

Reads the current wallust palette (the same colors.json the shell consumes) and
prints one tool's themed config to stdout. Called by integrations.sh whenever an
integration is (re)built, so every enabled tool follows the wallpaper.

    integrations-render.py <starship-palette|cava|btop|spotify-theme|codium>

Palette source, first that exists:
    ~/.config/velumeron/quickshell/colors.json   (written live by wallust)
    ~/.cache/wallust/colors.json
Falls back to a static velumeron scheme so output is always valid.
"""
import json
import os
import sys

HOME = os.path.expanduser("~")
CFG = os.environ.get("XDG_CONFIG_HOME", f"{HOME}/.config")
CACHE = os.environ.get("XDG_CACHE_HOME", f"{HOME}/.cache")

FALLBACK = {
    "background": "#040308", "foreground": "#e6e2f0",
    "color0": "#11101a", "color1": "#f7768e", "color2": "#9ece6a",
    "color3": "#566f82", "color4": "#a78bfa", "color5": "#2e828a",
    "color6": "#63d0c0", "color7": "#b9b4cc", "color8": "#5a5670",
    "color9": "#f7768e", "color10": "#9ece6a", "color11": "#e0af68",
    "color12": "#a78bfa", "color13": "#2e828a", "color14": "#63d0c0",
    "color15": "#d6ded8",
}


def load_palette():
    for path in (f"{CFG}/velumeron/quickshell/colors.json",
                 f"{CACHE}/wallust/colors.json"):
        try:
            with open(path) as fh:
                d = json.load(fh)
            # accept only if it carries the fields we need
            if "background" in d and "color0" in d:
                return {k: d[k] for k in FALLBACK if k in d} | \
                       {k: FALLBACK[k] for k in FALLBACK if k not in d}
        except (OSError, ValueError):
            continue
    return dict(FALLBACK)


# ── colour helpers ─────────────────────────────────────────────────────────
def _rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _hex(rgb):
    return "#" + "".join(f"{max(0, min(255, round(c))):02x}" for c in rgb)


def mix(a, b, t):
    ra, rb = _rgb(a), _rgb(b)
    return _hex(tuple(ra[i] + (rb[i] - ra[i]) * t for i in range(3)))


def ramp(stops, n):
    """Evenly sample n colours along a piecewise-linear gradient of hex stops."""
    if n == 1:
        return [stops[0]]
    out = []
    seg = len(stops) - 1
    for i in range(n):
        pos = i / (n - 1) * seg
        lo = min(int(pos), seg - 1)
        out.append(mix(stops[lo], stops[lo + 1], pos - lo))
    return out


# ── renderers ──────────────────────────────────────────────────────────────
def _lum(hexv):
    r, g, b = _rgb(hexv)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255


def r_starship(p):
    # Pastel Powerline shape (the official starship preset) driven by our palette.
    # Six powerline segments, each a distinct wallust colour, plus a per-segment
    # text colour picked for contrast (dark on light segments, light on dark) so
    # labels stay readable whatever the wallpaper yields. Named "velumeron" (not
    # "noctalia") so the shell's own palette merge can't collide with it.
    c = p
    # Neutral near-black / near-white for the label text — readable on any
    # segment colour, and doesn't inherit a weird saturated wallust foreground.
    def fg_for(bg):
        return c["color0"] if _lum(bg) > 0.55 else c["color15"]
    segs = {"os": c["color4"], "dir": c["color5"], "git": c["color3"],
            "lang": c["color6"], "docker": c["color2"], "time": c["color1"]}
    out = ["[palettes.velumeron]"]
    for name, bg in segs.items():
        out.append(f'{name}_bg = "{bg}"')
        out.append(f'{name}_fg = "{fg_for(bg)}"')
    out.append(f'ok  = "{c["color2"]}"')
    out.append(f'err = "{c["color1"]}"')
    return "\n".join(out) + "\n"


def r_cava(p):
    lo, hi = p["color5"], p["color4"]
    cols = ramp([lo, mix(lo, hi, 0.5), hi, mix(hi, p["foreground"], 0.35)], 8)
    lines = ["[color]",
             "# velumeron — gradient tracks the wallpaper palette (wallust)",
             "gradient = 1", "gradient_count = 8"]
    for i, col in enumerate(cols, 1):
        lines.append(f"gradient_color_{i} = '{col}'")
    return "\n".join(lines) + "\n"


def r_btop(p):
    bg, fg = p["background"], p["foreground"]
    a, b, c3 = p["color5"], p["color4"], p["color6"]
    box = mix(bg, fg, 0.30)
    g = [a, mix(a, b, 0.5), b]  # cold→hot ramp reused by every graph
    th = {
        "main_bg": bg, "main_fg": fg,
        "title": b, "hi_fg": c3,
        "selected_bg": mix(bg, a, 0.35), "selected_fg": fg,
        "inactive_fg": p["color8"], "proc_misc": c3,
        "cpu_box": box, "mem_box": box, "net_box": box, "proc_box": box,
        "div_line": mix(bg, fg, 0.22),
        "temp_start": g[0], "temp_mid": g[1], "temp_end": g[2],
        "cpu_start": g[0], "cpu_mid": g[1], "cpu_end": g[2],
        "free_start": g[0], "free_mid": g[1], "free_end": g[2],
        "cached_start": g[0], "cached_mid": g[1], "cached_end": g[2],
        "available_start": g[0], "available_mid": g[1], "available_end": g[2],
        "used_start": g[0], "used_mid": g[1], "used_end": g[2],
        "download_start": g[0], "download_mid": g[1], "download_end": g[2],
        "upload_start": g[0], "upload_mid": g[1], "upload_end": g[2],
    }
    out = ["# btop theme — velumeron (generated from the wallust palette)"]
    out += [f'theme[{k}]="{v}"' for k, v in th.items()]
    return "\n".join(out) + "\n"


def r_spotify(p):
    c = p
    pal = {
        "background": c["background"], "foreground": c["foreground"],
        "black": c["color0"], "red": c["color1"], "green": c["color2"],
        "yellow": c["color3"], "blue": c["color4"], "magenta": c["color5"],
        "cyan": c["color6"], "white": c["color7"],
        "bright_black": c["color8"], "bright_red": c["color9"],
        "bright_green": c["color10"], "bright_yellow": c["color11"],
        "bright_blue": c["color12"], "bright_magenta": c["color13"],
        "bright_cyan": c["color14"], "bright_white": c["color15"],
    }
    out = ['[[themes]]', 'name = "velumeron"', '[themes.palette]']
    out += [f'{k} = "{v}"' for k, v in pal.items()]
    out += ['[themes.component_style]',
            'selection = { bg = "%s", fg = "%s", modifiers = ["Bold"] }'
            % (mix(c["background"], c["color4"], 0.35), c["foreground"]),
            'playback_track = { fg = "%s", modifiers = ["Bold"] }' % c["color4"],
            'like = { fg = "%s" }' % c["color5"]]
    return "\n".join(out) + "\n"


def r_codium(p):
    c = p
    bg, fg = c["background"], c["foreground"]
    accent, accent2 = c["color4"], c["color5"]
    panel = mix(bg, fg, 0.06)
    panel2 = mix(bg, fg, 0.10)
    border = mix(bg, fg, 0.16)
    muted = c["color8"]
    theme = {
        "name": "Velumeron Wallust",
        "type": "dark",
        "colors": {
            "editor.background": bg, "editor.foreground": fg,
            "editorCursor.foreground": accent,
            "editor.selectionBackground": mix(bg, accent, 0.30),
            "editor.lineHighlightBackground": panel,
            "editorLineNumber.foreground": muted,
            "editorLineNumber.activeForeground": accent,
            "sideBar.background": mix(bg, "#000000", 0.15),
            "sideBar.foreground": fg, "sideBarTitle.foreground": accent,
            "activityBar.background": mix(bg, "#000000", 0.25),
            "activityBar.foreground": accent,
            "activityBarBadge.background": accent,
            "activityBarBadge.foreground": bg,
            "statusBar.background": accent, "statusBar.foreground": bg,
            "statusBar.noFolderBackground": accent2,
            "titleBar.activeBackground": mix(bg, "#000000", 0.20),
            "titleBar.activeForeground": fg,
            "tab.activeBackground": bg, "tab.inactiveBackground": panel,
            "tab.activeForeground": fg, "tab.inactiveForeground": muted,
            "tab.activeBorderTop": accent,
            "panel.background": bg, "panel.border": border,
            "editorGroupHeader.tabsBackground": panel,
            "editorWidget.background": panel2,
            "input.background": panel2, "input.border": border,
            "dropdown.background": panel2,
            "focusBorder": accent, "foreground": fg,
            "widget.shadow": "#00000066",
            "button.background": accent, "button.foreground": bg,
            "button.hoverBackground": mix(accent, fg, 0.15),
            "list.activeSelectionBackground": mix(bg, accent, 0.30),
            "list.activeSelectionForeground": fg,
            "list.hoverBackground": panel2,
            "list.highlightForeground": accent,
            "scrollbarSlider.background": mix(bg, fg, 0.20) + "80",
            "badge.background": accent, "badge.foreground": bg,
            "progressBar.background": accent,
            "terminal.background": bg, "terminal.foreground": fg,
            "terminal.ansiBlack": c["color0"], "terminal.ansiRed": c["color1"],
            "terminal.ansiGreen": c["color2"], "terminal.ansiYellow": c["color3"],
            "terminal.ansiBlue": c["color4"], "terminal.ansiMagenta": c["color5"],
            "terminal.ansiCyan": c["color6"], "terminal.ansiWhite": c["color7"],
            "terminal.ansiBrightBlack": c["color8"],
            "terminal.ansiBrightRed": c["color9"],
            "terminal.ansiBrightGreen": c["color10"],
            "terminal.ansiBrightYellow": c["color11"],
            "terminal.ansiBrightBlue": c["color12"],
            "terminal.ansiBrightMagenta": c["color13"],
            "terminal.ansiBrightCyan": c["color14"],
            "terminal.ansiBrightWhite": c["color15"],
        },
        "tokenColors": [
            {"scope": ["comment", "punctuation.definition.comment"],
             "settings": {"foreground": muted, "fontStyle": "italic"}},
            {"scope": ["string", "constant.other.symbol"],
             "settings": {"foreground": c["color2"]}},
            {"scope": ["constant.numeric", "constant.language"],
             "settings": {"foreground": c["color3"]}},
            {"scope": ["keyword", "storage", "storage.type"],
             "settings": {"foreground": c["color5"]}},
            {"scope": ["entity.name.function", "support.function"],
             "settings": {"foreground": c["color4"]}},
            {"scope": ["entity.name.type", "support.type", "support.class"],
             "settings": {"foreground": c["color6"]}},
            {"scope": ["variable", "variable.other"],
             "settings": {"foreground": fg}},
            {"scope": ["entity.name.tag"],
             "settings": {"foreground": c["color1"]}},
            {"scope": ["entity.other.attribute-name"],
             "settings": {"foreground": c["color4"], "fontStyle": "italic"}},
        ],
    }
    return json.dumps(theme, indent=2) + "\n"


RENDERERS = {
    "starship-palette": r_starship,
    "cava": r_cava,
    "btop": r_btop,
    "spotify-theme": r_spotify,
    "codium": r_codium,
}

# 2×2 cell → one Unicode quadrant-block glyph (TL, TR, BL, BR filled?).
_QUAD = {
    (0, 0, 0, 0): " ", (1, 0, 0, 0): "▘", (0, 1, 0, 0): "▝", (1, 1, 0, 0): "▀",
    (0, 0, 1, 0): "▖", (1, 0, 1, 0): "▌", (0, 1, 1, 0): "▞", (1, 1, 1, 0): "▛",
    (0, 0, 0, 1): "▗", (1, 0, 0, 1): "▚", (0, 1, 0, 1): "▐", (1, 1, 0, 1): "▜",
    (0, 0, 1, 1): "▄", (1, 0, 1, 1): "▙", (0, 1, 1, 1): "▟", (1, 1, 1, 1): "█",
}


def render_raven(path, factor=1, color="35"):
    """Downscale an ASCII silhouette (any non-space char = filled) to compact
    block art via Unicode quadrant glyphs. Each output glyph maps a (2·factor)×
    (2·factor) source area onto its four quadrants; each quadrant is one source
    cell (factor=1 → exactly one source char, lossless), or the majority of a
    factor×factor patch when factor>1. Wrapped in a themed ANSI colour so the
    logo follows the wallpaper."""
    with open(path) as fh:
        raw = fh.read().split("\n")
    while raw and raw[-1].strip() == "":
        raw.pop()
    h = len(raw)
    w = max((len(r) for r in raw), default=0)

    def filled(x, y):
        return 1 if (0 <= y < h and 0 <= x < len(raw[y]) and raw[y][x] != " ") else 0

    def quad(bx, by):        # one quadrant = majority of a factor×factor patch
        if factor == 1:
            return filled(bx, by)
        on = sum(filled(bx + dx, by + dy) for dy in range(factor) for dx in range(factor))
        return 1 if on * 2 >= factor * factor else 0

    cw = 2 * factor          # source cells spanned per output glyph
    out = []
    for y in range(0, h, cw):
        row = ""
        for x in range(0, w, cw):
            tl = quad(x, y)
            tr = quad(x + factor, y)
            bl = quad(x, y + factor)
            br = quad(x + factor, y + factor)
            row += _QUAD[(tl, tr, bl, br)]
        out.append(row.rstrip())
    # drop empty rows top/bottom and dedent common left blanks → tight bounding box
    while out and not out[0].strip():
        out.pop(0)
    while out and not out[-1].strip():
        out.pop()
    filledrows = [r for r in out if r.strip()]
    if filledrows:
        indent = min(len(r) - len(r.lstrip(" ")) for r in filledrows)
        out = [r[indent:] for r in out]
    body = "\n".join(out).rstrip("\n")
    return "\033[%sm%s\033[0m\n" % (color, body)


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "raven":
        factor = int(sys.argv[3]) if len(sys.argv) > 3 else 1
        sys.stdout.write(render_raven(sys.argv[2], factor))
        return
    if len(sys.argv) != 2 or sys.argv[1] not in RENDERERS:
        sys.stderr.write("usage: integrations-render.py <%s|raven <file> [factor]>\n"
                         % "|".join(RENDERERS))
        sys.exit(2)
    sys.stdout.write(RENDERERS[sys.argv[1]](load_palette()))


if __name__ == "__main__":
    main()
