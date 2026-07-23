# velumeron-dynamic — wallust-following cursor theme

The **source** for Velumeron's own mouse-cursor theme. It is *not* an installed
theme on its own — [`assets/scripts/cursor-build.py`](../../assets/scripts/cursor-build.py)
recolours these SVGs from the live wallust palette and compiles them into
`~/.local/share/icons/velumeron-dynamic/` (Hyprcursor **and** Xcursor) on every
palette change, so the pointer follows the wallpaper like every other themed tool.

## Layout

    meta.json          per-cursor metadata distilled from Bibata's build config:
                       { name, hotspot [x,y] on a 256px canvas, symlinks, and
                         either "svg" (static) or "frames"+"delay" (animated) }
    svg/<name>.svg     static shapes
    svg/<name>/        animated shapes (frame-000.svg … frame-NNN.svg)

## Placeholder colours (substituted at build time)

| placeholder | role     | velumeron-dynamic mapping                              |
|-------------|----------|--------------------------------------------------------|
| `#00FF00`   | body     | bar background (color0) mixed toward the accent (color3), lifted toward neutral grey |
| `#0000FF`   | outline  | **bar border** (boNormal/color5), damped toward the body |
| `#FF0000`   | detail   | a touch darker than the body                           |
| `#FCB813` `#F05024` `#7EBA41` `#32A0DA` | wait-spinner | bar-border tints |

The cursor mirrors the **bar**: a dark, softly-tinted body with the bar's own
(damped) border colour, so the pointer reads as the same material as the bar.
The mix/damp/lighten amounts are named constants at the top of `cursor-build.py`
(`BODY_ACCENT_MIX`, `BORDER_DAMP`, `BODY_LIGHTEN`) — tune to taste.

## Attribution

Shapes are derived from **Bibata Cursor** (Modern variant) by Abdulkaiz Khatri —
<https://github.com/ful1e5/Bibata_Cursor>, licensed **GPL-3.0** (see
`LICENSE-Bibata`). Only the three placeholder colours are re-mapped; the vector
geometry is unmodified.
