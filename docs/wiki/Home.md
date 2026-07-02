# Velumeron Wiki

Velumeron is a modular Hyprland desktop: a Lua-based Hyprland config (**hypr.lua**), a native
**Quickshell** shell (bar, menus, OSD, notifications, settings, launcher), a per-monitor
**wallpaper engine** (static + live video via a libmpv plugin) and wallpaper-driven theming via
**wallust** — one cohesive, theme-aware environment.

This wiki is the user-facing documentation. The engineering deep-dive lives in
[../ARCHITECTURE.md](../ARCHITECTURE.md).

## Pages

| Page | What it covers |
| --- | --- |
| [Getting Started](Getting-Started.md) | First launch, opening the settings, essential keybinds |
| [Bar](Bar.md) | Bar modes (dock / float / frame), edges, groups, per-monitor setup |
| [Bar Modules](Bar-Modules.md) | Every bar module and its gear options |
| [Calendar & Tasks](Calendar-and-Tasks.md) | CalDAV accounts (Nextcloud, Vikunja), the clock menu, quick-add |
| [Wallpapers & Theming](Wallpapers-and-Theming.md) | Wallpaper engine, live video, quick menu, wallust colour flow, UI styles |
| [Zones](Zones.md) | FancyZones for floating windows |
| [Overlays](Overlays.md) | OSD, notifications, launcher, clipboard, taskbar, window tags, hot corners, btop dropdown |
| [IPC Reference](IPC-Reference.md) | Every `qs ipc` target — for keybinds and scripting |
| [Settings Reference](Settings-Reference.md) | Every `settings.json` key with defaults |
| [Scripts Reference](Scripts-Reference.md) | The `assets/scripts` toolbox |
| [Troubleshooting](Troubleshooting.md) | Known pitfalls and how to diagnose them |
| [Accessibility](Accessibility.md) | Current state and the accessibility roadmap |

## The big picture

```
wallpaper change (quick menu / IPC / auto-timer)
        │
        ▼
wallpaper-set.sh ──► wallpapers.json ──► Quickshell WallpaperWindow (mpv plugin: GPU crossfades)
        │
        └─► wallust ──► colors.json ──► Colors.qml (live recolour, no restart)
                   └──► colors.lua  ──► hypr.lua (borders etc., via hyprctl reload hook)
                   └──► kitty / GTK / Qt / rofi templates
```

- **Quickshell** runs from `quickshell/` and hot-reloads on file changes.
- **hypr.lua** is the Hyprland Lua config runtime — dispatchers are `hl.dsp.*`, dynamic rules and
  window ops go through `hyprctl eval` (see [Troubleshooting](Troubleshooting.md#hyprctl-speaks-lua)).
- **Settings** live in `~/.config/velumeron/gui/settings.json`, written by the settings UI and read
  live by the shell (`VtlConfig.qml`).
