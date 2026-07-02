# Wallpapers & Theming

## The wallpaper engine

Each monitor has a native background surface (no swww/mpvpaper). Static images crossfade on the
GPU; files with a video extension (`mp4`, `webm`, `mkv`, `avi`, `mov`) play as **live wallpapers**
through a bundled libmpv → QtQuick plugin. The engine watches
`~/.config/velumeron/quickshell/wallpapers.json` — whatever writes that file changes the wallpaper.

Transitions (fade, circle, diamond, wipe, blinds, slide, random + parameters) are picked in
Settings → Wallpaper.

> Live wallpapers require the shell to run with the OpenGL scene graph — always start it via
> `launch-quickshell.sh` (it exports `QSG_RHI_BACKEND=opengl` and builds the plugin on first run).

## Choosing wallpapers

- **Quick menu** — `Super + Alt + Space`, the Wallpaper bar module, or
  `qs … ipc call wallpaper toggle`. Tabs per monitor + a **Sets** tab; filter All / Static / Live.
- **Settings → Wallpaper** — the same browser plus folders, sets and auto-change configuration.

### Folders & subfolders

The wallpaper directories (horizontal/vertical, per-monitor overrides) are set via the gear in
Settings → Wallpaper. With **search subfolders** on, subdirectories are scanned too; with
**subfolder as sorting** on, both pickers show one captioned section per subfolder (subfolders
first, root files last as "Main").

### Sets

A set maps each monitor to a wallpaper — apply your whole multi-monitor arrangement with one
click.

### Auto-change

Settings → Wallpaper: off / silent / show (with a workspace showcase), interval, and order
(alphabetical or random, across all subfolders or grouped per subfolder).

## Colour flow (wallust)

Every wallpaper change re-derives the palette:

```
wallpaper-set.sh ─► wallust ─► colors.json   ─► Quickshell recolours LIVE (no restart)
                          ├──► colors.lua    ─► Hyprland borders (hyprctl reload hook)
                          ├──► kitty colors.conf, GTK, Qt, rofi templates
                          └──► terminal escape sequences (best-effort, see note)
```

- The shell reads `colors.json` through a watched file — a theme change restyles every surface in
  place.
- Terminal recolouring is a separate best-effort pass: a blocked pseudo-terminal (e.g. an sftp
  mount's ssh pty) can never stall the pipeline again — templates and hooks always land first.

## UI style (Settings → Style)

- **UI STYLE**: `flat` (default), `cards`, `outlined` — one token set (`Style.qml`) drives radius,
  fills, borders and spacing of every shared control; switching restyles the whole shell live.
- **COLORFUL**: blends a little accent into surfaces — master switch + per-surface subs
  (bar / menus / OSD).
- **TRANSITION**: how surfaces meet the bar (concave fillet / straight), globally and per surface.
- **TEMPLATE / COLOURS**: palette-related options and manual colour tweaks.

The single accent everywhere is wallust's `color3` (`Colors.bgActive`); surfaces stay neutral.
