# Zones (FancyZones for floating windows)

Hold **Super** and drag a floating window: the zone layout fades in as soft accent fields on
every monitor. The zone under the cursor lights up — release there and the window snaps exactly
into it. Release outside any zone and the window stays where you dropped it.

## Configuration (Settings → Zones)

- **Enable zones** — master switch (off by default)
- **Zone gap** — pixel gap between zones
- **Layout** — pick one of the presets, each drawn as a mini preview:
  Halves · Thirds · Focus (25/50/25) · Main + side · Main + stack · Quarters · Rows

Zones are laid out inside each monitor's free area — bars and other reserved strips are excluded,
so a snapped window never hides under the bar.

## How it works (and why it's robust)

The picked layout is stored **resolved** (`fancy_zones_resolved`, fractions of the usable area) —
one source of truth shared by:

- the **overlay** (`quickshell/zones/ZoneOverlay.qml`) — input-transparent fields, highlight
  follows the cursor,
- the **snap** (`hypr.lua/modules/fancyzones.lua`) — runs inside the compositor on release.

What you see is exactly where it snaps. The compositor side never calls external tools in the
input path; quickshell pre-writes everything it needs (zones, gap, per-monitor usable areas) to
`$XDG_RUNTIME_DIR/velumeron-zones.state`.

## IPC

```bash
qs -p $VELUMERON_DIR/quickshell ipc call zones open    # show the fields (debugging)
qs -p $VELUMERON_DIR/quickshell ipc call zones close
```

## Limitations

- Zones apply to **floating** windows only (tiled windows follow the Hyprland layout).
- One global layout for all monitors (per-monitor layouts are a planned extension).
