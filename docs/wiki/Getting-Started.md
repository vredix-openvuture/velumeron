# Getting Started

## Installation

Run the bootstrap from the repository root:

```bash
./welcome_to_velumeron.sh
```

It installs the dependencies (see [../dependencies.md](../dependencies.md)), copies the user
configuration to `~/.config/velumeron/`, wires the Hyprland entry point
(`~/.config/hypr/hyprland.lua` → the repo's `hypr.lua/`) and configures the monitors
automatically with their best mode. The only question it asks is whether to install packages.

On the first shell start the **setup wizard** opens (a quickshell overlay): workspaces,
wallpaper, role/quick apps and avatar — every step optional, everything changeable later in
Settings. After a package update the same window opens once as a **"What's new"** report, fed
by `CHANGELOG.md` (`VERSION` vs. the stamp in `~/.config/velumeron/gui/last-seen-version`).
Force it any time with `velumeron --onboarding` (wizard — writes real config!) or
`velumeron --onboarding update` (changelog).

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
The menu grows out of the bar corner; the rail on the left (scrollable) switches between
sections: Home, Launcher, Bar, Style, Wallpaper, OSD, Notifications, Calendar, Lockscreen,
Corners, Taskbar, Zones, Window tags, Monitors, Workspaces, Autostart, Quick access,
Peripherals, Window rules.

Shell-level controls write `settings.json` immediately — the shell reacts live. The
Hyprland-level sections (Monitors, Workspaces, Autostart, Quick access, Peripherals, Window
rules) stage their edits and write `user_settings.lua` on **Apply** (via
`assets/scripts/user-settings-io.py`), followed by one `hyprctl reload`. Monitor applies show
a 15-second Keep/Revert countdown in case a mode change blacks out a display.

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
| Resolution, scale, rotation, monitor arrangement | Settings → Monitors (drag to arrange) |
| Workspace names, default workspace, persistence | Settings → Workspaces |
| Autostart daemons / apps per workspace | Settings → Autostart |
| SUPER+F1–F12 quick apps | Settings → Quick access |
| Cursor theme & size | Settings → Peripherals |
| Floating / transparent window patterns | Settings → Window rules |
| Move / restyle the bar, add modules | Settings → Bar |
| Change wallpaper folders, auto-change | Settings → Wallpaper (gear icon for paths) |
| Connect Nextcloud / Vikunja | Settings → Calendar |
| Define snap zones for floats | Settings → Zones |
| Change the UI look (flat / cards / outlined) | Settings → Style |
| Tune popup positions / sizes | Settings → OSD |
