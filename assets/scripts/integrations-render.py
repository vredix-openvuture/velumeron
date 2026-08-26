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


def r_nvim(p):
    """A standalone Neovim colour scheme, generated from the wallust palette.

    Emitted as a real `colors/velumeron.lua`, not as a plugin: that is the one
    shape every Neovim understands, so `:colorscheme velumeron` works in LazyVim,
    in a hand-written init.lua and in a bare nvim with no plugin manager at all.

    The groups below are the neovim built-ins plus the treesitter `@...` captures
    every modern config highlights with. Plugin-specific groups are deliberately
    absent: they nearly all link to these, so the whole ecosystem follows without
    this file having to know a single plugin's name.
    """
    c = p
    bg, fg = c["background"], c["foreground"]
    accent, accent2 = c["color4"], c["color5"]
    red, green, yellow, cyan = c["color1"], c["color2"], c["color3"], c["color6"]
    muted = c["color8"]
    panel = mix(bg, fg, 0.06)          # cursor line, status line
    panel2 = mix(bg, fg, 0.10)         # floats, popup menu
    border = mix(bg, fg, 0.18)
    sel = mix(bg, accent, 0.30)        # visual selection, popup selection
    dim = mix(bg, fg, 0.45)            # punctuation, folds

    groups = [
        # ── editor chrome ──────────────────────────────────────────────────
        ("Normal", {"fg": fg, "bg": bg}),
        ("NormalNC", {"fg": fg, "bg": bg}),
        ("NormalFloat", {"fg": fg, "bg": panel2}),
        ("FloatBorder", {"fg": border, "bg": panel2}),
        ("FloatTitle", {"fg": accent, "bg": panel2, "bold": True}),
        ("ColorColumn", {"bg": panel}),
        ("Conceal", {"fg": muted}),
        ("Cursor", {"fg": bg, "bg": accent}),
        ("lCursor", {"fg": bg, "bg": accent}),
        ("CursorIM", {"fg": bg, "bg": accent}),
        ("CursorLine", {"bg": panel}),
        ("CursorColumn", {"bg": panel}),
        ("Directory", {"fg": accent}),
        ("EndOfBuffer", {"fg": bg}),
        ("ErrorMsg", {"fg": red, "bold": True}),
        ("VertSplit", {"fg": border}),
        ("WinSeparator", {"fg": border}),
        ("Folded", {"fg": dim, "bg": panel}),
        ("FoldColumn", {"fg": muted, "bg": bg}),
        ("SignColumn", {"fg": muted, "bg": bg}),
        ("IncSearch", {"fg": bg, "bg": accent2}),
        ("CurSearch", {"fg": bg, "bg": accent2}),
        ("Search", {"fg": bg, "bg": yellow}),
        ("Substitute", {"fg": bg, "bg": red}),
        ("LineNr", {"fg": muted}),
        ("CursorLineNr", {"fg": accent, "bold": True}),
        ("MatchParen", {"fg": accent2, "bold": True}),
        ("ModeMsg", {"fg": fg, "bold": True}),
        ("MoreMsg", {"fg": accent}),
        ("MsgArea", {"fg": fg}),
        ("MsgSeparator", {"fg": border}),
        ("NonText", {"fg": muted}),
        ("Pmenu", {"fg": fg, "bg": panel2}),
        ("PmenuSel", {"fg": fg, "bg": sel, "bold": True}),
        ("PmenuSbar", {"bg": panel2}),
        ("PmenuThumb", {"bg": border}),
        ("PmenuMatch", {"fg": accent, "bold": True}),
        ("PmenuMatchSel", {"fg": accent, "bg": sel, "bold": True}),
        ("Question", {"fg": accent}),
        ("QuickFixLine", {"bg": sel}),
        ("SpecialKey", {"fg": muted}),
        ("StatusLine", {"fg": fg, "bg": panel}),
        ("StatusLineNC", {"fg": muted, "bg": panel}),
        ("TabLine", {"fg": muted, "bg": panel}),
        ("TabLineFill", {"bg": mix(bg, "#000000", 0.20)}),
        ("TabLineSel", {"fg": bg, "bg": accent, "bold": True}),
        ("Title", {"fg": accent, "bold": True}),
        ("Visual", {"bg": sel}),
        ("VisualNOS", {"bg": sel}),
        ("WarningMsg", {"fg": yellow}),
        ("Whitespace", {"fg": mix(bg, fg, 0.20)}),
        ("WildMenu", {"fg": bg, "bg": accent}),
        ("Winbar", {"fg": muted, "bg": bg}),
        ("WinbarNC", {"fg": muted, "bg": bg}),

        # ── syntax, the legacy group names ─────────────────────────────────
        ("Comment", {"fg": muted, "italic": True}),
        ("Constant", {"fg": yellow}),
        ("String", {"fg": green}),
        ("Character", {"fg": green}),
        ("Number", {"fg": yellow}),
        ("Boolean", {"fg": yellow}),
        ("Float", {"fg": yellow}),
        ("Identifier", {"fg": fg}),
        ("Function", {"fg": accent}),
        ("Statement", {"fg": accent2}),
        ("Conditional", {"fg": accent2}),
        ("Repeat", {"fg": accent2}),
        ("Label", {"fg": accent2}),
        ("Operator", {"fg": mix(fg, accent2, 0.45)}),
        ("Keyword", {"fg": accent2}),
        ("Exception", {"fg": red}),
        ("PreProc", {"fg": cyan}),
        ("Include", {"fg": accent2}),
        ("Define", {"fg": accent2}),
        ("Macro", {"fg": cyan}),
        ("PreCondit", {"fg": accent2}),
        ("Type", {"fg": cyan}),
        ("StorageClass", {"fg": accent2}),
        ("Structure", {"fg": cyan}),
        ("Typedef", {"fg": cyan}),
        ("Special", {"fg": red}),
        ("SpecialChar", {"fg": red}),
        ("Tag", {"fg": red}),
        ("Delimiter", {"fg": dim}),
        ("SpecialComment", {"fg": muted, "italic": True}),
        ("Debug", {"fg": red}),
        ("Underlined", {"underline": True}),
        ("Error", {"fg": red}),
        ("Todo", {"fg": bg, "bg": yellow, "bold": True}),
        ("Added", {"fg": green}),
        ("Changed", {"fg": yellow}),
        ("Removed", {"fg": red}),

        # ── diff ────────────────────────────────────────────────────────────
        ("DiffAdd", {"bg": mix(bg, green, 0.20)}),
        ("DiffChange", {"bg": mix(bg, yellow, 0.14)}),
        ("DiffDelete", {"bg": mix(bg, red, 0.20)}),
        ("DiffText", {"bg": mix(bg, yellow, 0.32)}),

        # ── diagnostics (LSP) ───────────────────────────────────────────────
        ("DiagnosticError", {"fg": red}),
        ("DiagnosticWarn", {"fg": yellow}),
        ("DiagnosticInfo", {"fg": accent}),
        ("DiagnosticHint", {"fg": cyan}),
        ("DiagnosticOk", {"fg": green}),
        ("DiagnosticUnderlineError", {"undercurl": True, "sp": red}),
        ("DiagnosticUnderlineWarn", {"undercurl": True, "sp": yellow}),
        ("DiagnosticUnderlineInfo", {"undercurl": True, "sp": accent}),
        ("DiagnosticUnderlineHint", {"undercurl": True, "sp": cyan}),
        ("DiagnosticVirtualTextError", {"fg": red, "bg": mix(bg, red, 0.12)}),
        ("DiagnosticVirtualTextWarn", {"fg": yellow, "bg": mix(bg, yellow, 0.12)}),
        ("DiagnosticVirtualTextInfo", {"fg": accent, "bg": mix(bg, accent, 0.12)}),
        ("DiagnosticVirtualTextHint", {"fg": cyan, "bg": mix(bg, cyan, 0.12)}),

        # ── LSP extras ──────────────────────────────────────────────────────
        ("LspReferenceText", {"bg": mix(bg, fg, 0.14)}),
        ("LspReferenceRead", {"bg": mix(bg, fg, 0.14)}),
        ("LspReferenceWrite", {"bg": mix(bg, accent2, 0.22)}),
        ("LspInlayHint", {"fg": muted, "bg": panel, "italic": True}),
        ("LspSignatureActiveParameter", {"fg": accent, "bold": True}),
        ("LspCodeLens", {"fg": muted, "italic": True}),

        # ── spelling ────────────────────────────────────────────────────────
        ("SpellBad", {"undercurl": True, "sp": red}),
        ("SpellCap", {"undercurl": True, "sp": yellow}),
        ("SpellLocal", {"undercurl": True, "sp": cyan}),
        ("SpellRare", {"undercurl": True, "sp": accent2}),

        # ── treesitter captures ─────────────────────────────────────────────
        ("@variable", {"fg": fg}),
        ("@variable.builtin", {"fg": red, "italic": True}),
        ("@variable.parameter", {"fg": mix(fg, cyan, 0.45)}),
        ("@variable.member", {"fg": cyan}),
        ("@property", {"fg": cyan}),
        ("@field", {"fg": cyan}),
        ("@constant", {"fg": yellow}),
        ("@constant.builtin", {"fg": yellow, "italic": True}),
        ("@constant.macro", {"fg": cyan}),
        ("@module", {"fg": fg}),
        ("@label", {"fg": accent2}),
        ("@string", {"fg": green}),
        ("@string.escape", {"fg": red}),
        ("@string.special", {"fg": red}),
        ("@string.regexp", {"fg": red}),
        ("@character", {"fg": green}),
        ("@boolean", {"fg": yellow}),
        ("@number", {"fg": yellow}),
        ("@function", {"fg": accent}),
        ("@function.builtin", {"fg": accent, "italic": True}),
        ("@function.call", {"fg": accent}),
        ("@function.method", {"fg": accent}),
        ("@function.method.call", {"fg": accent}),
        ("@constructor", {"fg": cyan}),
        ("@operator", {"fg": mix(fg, accent2, 0.45)}),
        ("@keyword", {"fg": accent2}),
        ("@keyword.function", {"fg": accent2}),
        ("@keyword.operator", {"fg": accent2}),
        ("@keyword.return", {"fg": accent2}),
        ("@keyword.import", {"fg": accent2}),
        ("@keyword.exception", {"fg": red}),
        ("@type", {"fg": cyan}),
        ("@type.builtin", {"fg": cyan, "italic": True}),
        ("@type.definition", {"fg": cyan}),
        ("@attribute", {"fg": accent, "italic": True}),
        ("@punctuation.delimiter", {"fg": dim}),
        ("@punctuation.bracket", {"fg": dim}),
        ("@punctuation.special", {"fg": accent2}),
        ("@comment", {"fg": muted, "italic": True}),
        ("@comment.error", {"fg": bg, "bg": red, "bold": True}),
        ("@comment.warning", {"fg": bg, "bg": yellow, "bold": True}),
        ("@comment.note", {"fg": bg, "bg": accent, "bold": True}),
        ("@comment.todo", {"fg": bg, "bg": accent2, "bold": True}),
        ("@tag", {"fg": red}),
        ("@tag.builtin", {"fg": red}),
        ("@tag.attribute", {"fg": accent, "italic": True}),
        ("@tag.delimiter", {"fg": dim}),
        ("@markup.heading", {"fg": accent, "bold": True}),
        ("@markup.strong", {"fg": fg, "bold": True}),
        ("@markup.italic", {"fg": fg, "italic": True}),
        ("@markup.strikethrough", {"fg": muted, "strikethrough": True}),
        ("@markup.underline", {"underline": True}),
        ("@markup.link", {"fg": cyan, "underline": True}),
        ("@markup.link.label", {"fg": accent}),
        ("@markup.raw", {"fg": green}),
        ("@markup.list", {"fg": accent2}),
        ("@markup.quote", {"fg": muted, "italic": True}),
        ("@diff.plus", {"fg": green}),
        ("@diff.minus", {"fg": red}),
        ("@diff.delta", {"fg": yellow}),
    ]

    # Groups that are only ever an alias for one above. Kept as real links so a
    # plugin that overrides the target follows here too.
    links = [
        ("@lsp.type.class", "@type"),
        ("@lsp.type.comment", "@comment"),
        ("@lsp.type.enum", "@type"),
        ("@lsp.type.enumMember", "@constant"),
        ("@lsp.type.function", "@function"),
        ("@lsp.type.interface", "@type"),
        ("@lsp.type.keyword", "@keyword"),
        ("@lsp.type.method", "@function.method"),
        ("@lsp.type.namespace", "@module"),
        ("@lsp.type.parameter", "@variable.parameter"),
        ("@lsp.type.property", "@property"),
        ("@lsp.type.struct", "@type"),
        ("@lsp.type.type", "@type"),
        ("@lsp.type.typeParameter", "@type.definition"),
        ("@lsp.type.variable", "@variable"),
        ("NvimTreeNormal", "Normal"),
        ("NeoTreeNormal", "Normal"),
        ("TelescopeNormal", "NormalFloat"),
        ("TelescopeBorder", "FloatBorder"),
        ("SnacksNormal", "NormalFloat"),
        ("SnacksWinBar", "Title"),
        ("BlinkCmpMenu", "Pmenu"),
        ("BlinkCmpMenuSelection", "PmenuSel"),
        ("BlinkCmpDoc", "NormalFloat"),
        ("BlinkCmpDocBorder", "FloatBorder"),
        ("GitSignsAdd", "Added"),
        ("GitSignsChange", "Changed"),
        ("GitSignsDelete", "Removed"),
    ]

    def lua_val(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        return '"%s"' % v

    out = [
        "-- velumeron -- Neovim colour scheme generated from the wallust palette.",
        "--",
        "-- Do not edit: this file is rewritten on every wallpaper change by",
        "-- assets/scripts/integrations.sh. Switch the Neovim integration off in",
        "-- Settings, Integrations to get your own file back.",
        "",
        'vim.cmd("highlight clear")',
        'if vim.fn.exists("syntax_on") == 1 then',
        '  vim.cmd("syntax reset")',
        "end",
        'vim.o.background = "dark"',
        'vim.g.colors_name = "velumeron"',
        "",
        "local hi = vim.api.nvim_set_hl",
        "",
    ]
    for name, spec in groups:
        body = ", ".join("%s = %s" % (k, lua_val(v)) for k, v in spec.items())
        out.append('hi(0, "%s", { %s })' % (name, body))
    out.append("")
    for name, target in links:
        out.append('hi(0, "%s", { link = "%s" })' % (name, target))
    out.append("")
    out.append("-- :terminal, and every plugin that opens one.")
    for i, col in enumerate(_ansi(p)):
        out.append('vim.g.terminal_color_%d = "%s"' % (i, col))
    return "\n".join(out) + "\n"


# ── terminal emulators ─────────────────────────────────────────────────────
# One palette, five spellings of it. Each renderer emits ONLY the colour block —
# integrations.sh drops it into that emulator's base config at @VELUMERON_COLORS@,
# so the shape of the config (padding, opacity, bell) lives in integrations/terminals/
# and the colours are re-rendered on every theme change.
#
# The ansi order is the wallust one throughout: color0-7 normal, color8-15 bright.
def _ansi(p):
    return [p["color%d" % i] for i in range(16)]


def r_term_kitty(p):
    a = _ansi(p)
    sel_bg = mix(p["background"], p["color4"], 0.45)
    out = ["# colours — velumeron (wallust palette)",
           "foreground            %s" % p["foreground"],
           "background            %s" % p["background"],
           "cursor                %s" % a[4],
           "cursor_text_color     %s" % p["background"],
           "selection_foreground  %s" % p["foreground"],
           "selection_background  %s" % sel_bg,
           "url_color             %s" % a[6],
           "active_border_color   %s" % a[4],
           "inactive_border_color %s" % a[8],
           "bell_border_color     %s" % a[1],
           "active_tab_foreground   %s" % p["background"],
           "active_tab_background   %s" % a[4],
           "inactive_tab_foreground %s" % p["foreground"],
           "inactive_tab_background %s" % mix(p["background"], p["foreground"], 0.10)]
    out += ["color%-2d %s" % (i, a[i]) for i in range(16)]
    return "\n".join(out) + "\n"


def r_term_alacritty(p):
    a = _ansi(p)
    names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
    out = ["# colours — velumeron (wallust palette)",
           "[colors.primary]",
           'background = "%s"' % p["background"],
           'foreground = "%s"' % p["foreground"],
           "", "[colors.cursor]",
           'text = "%s"' % p["background"],
           'cursor = "%s"' % a[4],
           "", "[colors.selection]",
           'text = "%s"' % p["foreground"],
           'background = "%s"' % mix(p["background"], p["color4"], 0.45),
           "", "[colors.normal]"]
    out += ['%s = "%s"' % (n, a[i]) for i, n in enumerate(names)]
    out += ["", "[colors.bright]"]
    out += ['%s = "%s"' % (n, a[i + 8]) for i, n in enumerate(names)]
    return "\n".join(out) + "\n"


def r_term_foot(p):
    # foot wants bare RRGGBB (no '#'), and carries the window transparency in [colors].
    def bare(h):
        return h.lstrip("#")
    a = _ansi(p)
    out = ["# colours — velumeron (wallust palette)",
           "[colors]",
           "alpha=0.86",
           "background=%s" % bare(p["background"]),
           "foreground=%s" % bare(p["foreground"]),
           # `cursor=<text> <cursor>` — two colours on one key.
           "cursor=%s %s" % (bare(p["background"]), bare(a[4])),
           "selection-foreground=%s" % bare(p["foreground"]),
           "selection-background=%s" % bare(mix(p["background"], p["color4"], 0.45)),
           "urls=%s" % bare(a[6])]
    out += ["regular%d=%s" % (i, bare(a[i])) for i in range(8)]
    out += ["bright%d=%s" % (i, bare(a[i + 8])) for i in range(8)]
    return "\n".join(out) + "\n"


def r_term_wezterm(p):
    a = _ansi(p)
    def lua_list(cols):
        return "{ " + ", ".join("'%s'" % c for c in cols) + " }"
    out = ["-- colours — velumeron (wallust palette)",
           "config.colors = {",
           "  foreground = '%s'," % p["foreground"],
           "  background = '%s'," % p["background"],
           "  cursor_bg = '%s'," % a[4],
           "  cursor_fg = '%s'," % p["background"],
           "  cursor_border = '%s'," % a[4],
           "  selection_fg = '%s'," % p["foreground"],
           "  selection_bg = '%s'," % mix(p["background"], p["color4"], 0.45),
           "  ansi = %s," % lua_list(a[0:8]),
           "  brights = %s," % lua_list(a[8:16]),
           "}"]
    return "\n".join(out) + "\n"


def r_term_ghostty(p):
    a = _ansi(p)
    out = ["# colours — velumeron (wallust palette)",
           "background = %s" % p["background"],
           "foreground = %s" % p["foreground"],
           "cursor-color = %s" % a[4],
           "cursor-text = %s" % p["background"],
           "selection-foreground = %s" % p["foreground"],
           "selection-background = %s" % mix(p["background"], p["color4"], 0.45)]
    out += ["palette = %d=%s" % (i, a[i]) for i in range(16)]
    return "\n".join(out) + "\n"


# ── pywal drop-in (pywalfox and every other pywal-reading tool) ─────────────
# pywalfox reads ~/.cache/wal/colors.json; a long tail of scripts reads the plain
# ~/.cache/wal/colors (16 lines, one hex each). Both are written from OUR palette so
# a pywal-shaped tool follows the wallpaper without pywal ever being installed.
def r_pywal_colors(p):
    return "\n".join(_ansi(p)) + "\n"


def r_pywal_json(p):
    a = _ansi(p)
    d = {
        "wallpaper": _wallpaper_path(),
        "alpha": "100",
        "special": {"background": p["background"], "foreground": p["foreground"],
                    "cursor": p["foreground"]},
        "colors": {"color%d" % i: a[i] for i in range(16)},
    }
    return json.dumps(d, indent=4) + "\n"


def r_obsidian(p):
    """A CSS snippet defining --wl-* for an Obsidian vault.

    Deliberately only variables and nothing else: the snippet must not restyle Obsidian on its
    own, or enabling the integration would fight whatever theme is selected. It publishes the
    palette and stops there; a theme that reads --wl-* (Nexus does) picks it up, and a theme that
    does not is simply unaffected.
    """
    keys = ["background", "foreground"] + ["color%d" % i for i in range(16)]
    width = max(len(k) for k in keys)
    body = "\n".join("  --wl-%s:%s %s;" % (k, " " * (width - len(k)), p[k]) for k in keys)
    return (
        "/* Velumeron palette for Obsidian.\n"
        " * Generated on every wallpaper change by assets/scripts/integrations.sh.\n"
        " * Do not edit: your changes are overwritten. Switch the integration off in\n"
        " * Settings, Integrations to get your own file back.\n"
        " */\n"
        ":root {\n" + body + "\n}\n"
    )


def _wallpaper_path():
    """The wallpaper pywalfox reports. Best effort — the field must exist, not be right."""
    for path in (f"{CFG}/velumeron/quickshell/colors.json", f"{CACHE}/wallust/colors.json"):
        try:
            with open(path) as fh:
                d = json.load(fh)
            for k in ("wallpaper", "image", "path"):
                if isinstance(d.get(k), str) and d[k]:
                    return d[k]
        except (OSError, ValueError):
            continue
    return "None"


RENDERERS = {
    "starship-palette": r_starship,
    "cava": r_cava,
    "btop": r_btop,
    "spotify-theme": r_spotify,
    "codium": r_codium,
    "nvim": r_nvim,
    "term-kitty": r_term_kitty,
    "term-alacritty": r_term_alacritty,
    "term-foot": r_term_foot,
    "term-wezterm": r_term_wezterm,
    "term-ghostty": r_term_ghostty,
    "pywal-colors": r_pywal_colors,
    "pywal-json": r_pywal_json,
    "obsidian": r_obsidian,
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
