#!/usr/bin/env python3
# Map a fixed (ANSI-ordered) wallust colour scheme onto velumeron's *semantic* shell palette.
#
#   fixed-scheme-colors.py <scheme.json> <out.json>
#
# quickshell/colors.json is read ONLY by the shell (terminals/GTK/firefox get the raw ANSI scheme
# through wallust's other templates). Colors.qml reads the 16 slots through semantic aliases:
#
#   color0 bgPrimary · color1 bgElement · color2 bgSecondary · color3 bgActive(=accent) ·
#   color4 bgHover · color5 boNormal · color6 boActive · color7 fgPrimary · color8 fgMuted ·
#   color13 fgUrgent · color15 fgBright
#
# A raw ANSI scheme puts red/green/blue in slots 1/2/4/5/6, so surfaces and borders render as
# vivid clashing colours. Here we rebuild the surface/border slots and pick ONE signature accent.
#
# Surfaces are derived by stepping the background's *lightness* (in HLS), NOT by blending toward
# the foreground — a scheme with a dim foreground (e.g. Solarized's grey) would otherwise barely
# lift off the background and the whole UI turns to mush. Fixed lightness steps guarantee every
# surface, border and text tone stays clearly separated on any scheme.
import json
import sys
import colorsys


def hx(c):
    c = c.lstrip('#')
    return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16))


def rgb(t):
    return '#%02x%02x%02x' % tuple(max(0, min(255, round(v))) for v in t)


def to_hls(c):
    r, g, b = (x / 255.0 for x in hx(c))
    return colorsys.rgb_to_hls(r, g, b)   # (h, l, s)


def from_hls(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h, max(0.0, min(1.0, l)), max(0.0, min(1.0, s)))
    return rgb((r * 255, g * 255, b * 255))


def mix(a, b, t):
    a, b = hx(a), hx(b)
    return rgb(tuple(a[i] * (1 - t) + b[i] * t for i in range(3)))


def main():
    d = json.load(open(sys.argv[1]))
    sp = d.get('special', {})
    co = d.get('colors', {})

    bg = sp.get('background', co.get('color0', '#1e1e2e'))
    fg = sp.get('foreground', co.get('color7', '#cdd6f4'))
    white = '#ffffff'

    bh, bl, bs = to_hls(bg)
    dark = bl < 0.5
    sgn = 1.0 if dark else -1.0          # lighten dark themes, darken light ones
    # Keep a little of the base tint in the surfaces, but cap saturation so they stay neutral.
    ss = min(bs, 0.28)
    # A fixed lightness step compresses to near-zero *luminance* contrast on a very dark base,
    # so scale the steps up the darker the background is — keeps cards visibly lifted everywhere.
    kf = 1.0 + max(0.0, 0.22 - min(bl, 1.0 - bl)) * 3.2

    def surf(dl):
        """A surface `dl` lightness-steps away from the background (keeps the base hue)."""
        return from_hls(bh, bl + sgn * dl * kf, ss)

    # Signature accent: ANSI blue (color4) is the classic UI accent across these schemes
    # (dracula purple, nord frost, solarized blue, catppuccin blue, rose-pine foam…).
    accent = co.get('color4') or co.get('color5') or co.get('color6') or fg
    ah, al, as_ = to_hls(accent)
    # Guarantee the accent reads against the background — nudge its lightness apart if too close.
    if dark and al < bl + 0.22:
        accent = from_hls(ah, bl + 0.30, max(as_, 0.35))
    elif not dark and al > bl - 0.22:
        accent = from_hls(ah, bl - 0.30, max(as_, 0.35))

    # Foreground: keep the scheme's hue but guarantee readable contrast — a dim body text
    # (Solarized's #839496) gets lifted to a comfortable lightness.
    fh, fl, fs = to_hls(fg)
    fg_l = max(fl, bl + 0.55) if dark else min(fl, bl - 0.55)
    fg_primary = from_hls(fh, fg_l, fs)
    # Muted text: a clear step down from the primary, still well above the surfaces.
    fg_muted = from_hls(fh, (bl + sgn * 0.42), min(fs, 0.20))
    # Bright text (headings / active): pushed further toward white/black.
    fg_bright = from_hls(fh, min(0.95, fg_l + 0.12) if dark else max(0.05, fg_l - 0.12), fs)

    out = {
        'background': bg,
        'foreground': fg_primary,
        'color0':  bg,                        # bgPrimary   — the base surface
        'color1':  surf(0.075),               # bgElement   — lifted surface (cards/rows)
        'color2':  surf(0.125),               # bgSecondary — nested surface
        'color3':  accent,                    # bgActive    — the one accent
        'color4':  mix(surf(0.125), accent, 0.32),  # bgHover — accent-tinted surface
        'color5':  surf(0.22),                # boNormal    — clearly visible border
        'color6':  accent,                    # boActive    — accent border
        'color7':  fg_primary,                # fgPrimary
        'color8':  fg_muted,                  # fgMuted
        'color9':  co.get('color1', accent),  # keep the scheme's vivid accents for the few
        'color10': co.get('color2', accent),  # spots that use raw colours (colourful pops)
        'color11': co.get('color3', accent),
        'color12': co.get('color4', accent),
        'color13': co.get('color1', '#e06c75'),  # fgUrgent — the scheme's red
        'color14': co.get('color6', accent),
        'color15': fg_bright,                 # fgBright
    }
    json.dump(out, open(sys.argv[2], 'w'), indent=2)


if __name__ == '__main__':
    main()
