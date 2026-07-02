# Accessibility

Status quo, honest gaps, and the roadmap. Goal: Velumeron should be usable by people with low
vision, motor impairments, colour-vision deficiency and vestibular sensitivity — without a
separate "accessible mode" that looks worse.

## What already helps

- **Live theming with contrast guard** — wallust runs with `check_contrast = true`, so
  wallpaper-derived palettes keep readable fg/bg contrast.
- **One token system** — `Style.qml` centralises fonts, radii, fills and spacing; most surfaces
  react to a single change (the foundation every feature below builds on).
- **Configurable sizes** in many places (bar font/icon size, per-module sizes, OSD size, menu
  sizes, clipboard rows, window-tag font).
- **Keyboard-first overlays** — launcher, clipboard and window switcher are fully keyboard
  driven; overlays close on `Escape`.
- **No information by colour alone** in most status displays (icons + text accompany colour).

## Gaps (found in review)

1. **No global scale** — sizes are configurable but scattered; there is no single "make
   everything 125% bigger" control.
2. **Animations are unconditional** — every surface animates (morphs, glides, marquees, spinning
   sync icons). Nothing honours reduced-motion needs.
3. **Menus are mouse-only** — settings menu, calendar menu and flyouts have no focus order / arrow
   navigation; small hit targets (17px checkboxes, 24px mini switches, hover-only ✕ buttons).
4. **Hover-dependent affordances** — delete buttons, glides and tooltips appear only on hover
   (undiscoverable via keyboard, hard with tremor).
5. **No screen-reader story** — no `Accessible.*` roles/names on QML controls (Wayland layer-shell
   + Orca support is genuinely limited, but roles cost little and help where AT-SPI reaches).
6. **Colour-only zone/calendar coding** — calendar dots and zone highlights rely on hue; needs a
   pattern/shape fallback for colour-vision deficiency.
7. **Timing is fixed** — hot-corner dwell is configurable, but OSD duration, hover delays and
   double-click windows are one-size-fits-all.

## Roadmap

### Phase 1 — global tokens (small code, big effect)

Add to `Style.qml` + Settings → Style → *Accessibility* card:

- `a11y_scale` (1.0–1.5): multiplies `fsSection/fsLabel/fsSub/fsValue`, control heights and hit
  targets. Because every shared control reads the tokens, one setting scales the whole settings
  UI + menus.
- `a11y_reduce_motion` (bool): `Style.animMs(base)` helper returning 0 when on; migrate
  `Behavior`/`NumberAnimation` durations to it. Marquees become static ellipses; the settings-menu
  morph becomes a fade.
- `a11y_min_hit` (px, default 0): shared controls grow their MouseArea margins to reach it.

### Phase 2 — keyboard & focus

- Focus chain + arrow-key navigation in the settings menu (rail ↑/↓, content Tab order) and the
  calendar menu (grid arrows, Enter selects, `t` = today).
- Persistent (non-hover) affordances mode: show delete/edit icons always when
  `a11y_always_show_actions` is on.
- Visible focus ring token (accent outline) for every common control.

### Phase 3 — vision

- High-contrast palette mode: bypass wallust with a fixed WCAG-AA palette (or post-process the
  wallust palette to enforce ≥4.5:1 on text roles).
- Colour-independent coding: shapes/initials next to calendar dots, patterned zone highlight.
- Larger cursor + bar "XL" preset documented.

### Phase 4 — assistive tech & audio

- `Accessible.role/name/description` on common controls (Toggle, Stepper, Segmented, Dropdown…).
- Optional sound cues (notification urgency, zone snap, task complete) via a small `SoundFx`
  service — off by default.
- Screen-reader review with Orca on the GTK/portal dialogs the shell spawns.

### Measuring

Each phase should be tested with: 200% zoom text survival, keyboard-only walkthrough of every
settings page, a grayscale-filter pass (colour-independence), and `for-hyprland` reduced-motion
user feedback.
