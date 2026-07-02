# Getting Started

## Installation

Run the interactive installer from the repository root:

```bash
./welcome_to_velumeron.sh
```

It installs the dependencies (see [../dependencies.md](../dependencies.md)), copies the user
configuration to `~/.config/velumeron/` and wires the Hyprland entry point
(`~/.config/hypr/hyprland.lua` → the repo's `hypr.lua/`).

Two directories matter afterwards:

| Path | Role |
| --- | --- |
| `$VELUMERON_DIR` (the repo) | Package: QML sources, scripts, hypr.lua modules, assets |
| `~/.config/velumeron` (`$VELUMERON_USER_DIR`) | Your data: `gui/settings.json`, wallpapers config, generated colours, kitty config |

## First launch

The shell starts with Hyprland. To (re)start it manually always use the launch script — it builds
the mpv wallpaper plugin on first run and sets the required environment
(`QSG_RHI_BACKEND=opengl`, `QML_IMPORT_PATH`):

```bash
"$VELUMERON_DIR/assets/scripts/launch-quickshell.sh"
```

## The settings menu

Click the **Velumeron icon** in the bar (or bind `qs -p $VELUMERON_DIR/quickshell ipc call menu toggle`).
The menu grows out of the bar corner; the rail on the left switches between sections:
Home, Launcher, Bar, Style, Wallpaper, OSD, Notifications, Calendar, Lockscreen, Corners,
Taskbar, Zones, Window tags.

Every control writes `settings.json` immediately — there is no "Apply" button, the shell reacts live.

## Essential keybinds (defaults)

| Keys | Action |
| --- | --- |
| `Super + Space` | Application launcher |
| `Super + V` | Clipboard history |
| `Super + Tab` | Window switcher |
| `Super + Ctrl + Q` | Session menu (lock / suspend / logout / …) |
| `Super + Alt + Space` | Wallpaper quick menu |
| `Super + drag` | Move a floating window — with [Zones](Zones.md) enabled, snap fields appear |
| Click the clock | [Calendar & tasks menu](Calendar-and-Tasks.md) |
| Right-click the Performance module | btop dropdown terminal |

Keybinds live in `hypr.lua/modules/keybinds.lua`; the keybind cheatsheet overlay is available via
`qs … ipc call keybind all`.

## Where things are configured

| I want to… | Go to |
| --- | --- |
| Move / restyle the bar, add modules | Settings → Bar |
| Change wallpaper folders, auto-change | Settings → Wallpaper (gear icon for paths) |
| Connect Nextcloud / Vikunja | Settings → Calendar |
| Define snap zones for floats | Settings → Zones |
| Change the UI look (flat / cards / outlined) | Settings → Style |
| Tune popup positions / sizes | Settings → OSD |
