<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)"  srcset="assets/icons/velumeron_banner-white.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/icons/velumeron_banner-black.png">
  <img alt="Velumeron" src="assets/icons/velumeron_banner-black.png" width="520">
</picture>


<br>
<br>
<br>

**Velumeron** is a modular desktop for Wayland based Window Compositors.

</div>

A complete desktop shell — bar, notifications, OSD, launcher, lock screen, wallpaper engine,
window switcher — with every colour derived from your wallpaper.

Each of those is one switch. They are all on out of the box; turn off what you already have and
Velumeron stays out of that job instead of taking it over.

The compositor layer is Hyprland today, configured in Lua. The shell itself is layer-shell and
compositor-neutral — support for further wlroots compositors is on the way.


<br>
<br>

## Install

```sh
yay -S velumeron-git    or    paru -S velumeron-git
```

That is it. Installed from a terminal inside your running Hyprland, the package sets itself up on
the spot — config, monitors, services, shell — and the wizard opens for the few things only you can
answer. No re-login, no second command. Everything it asks is changeable later under Settings
(`Super+X`).

Installing from somewhere else (a TTY, a fresh box, another compositor)? Start it once with
`velumeron-session`.

From a checkout instead: `sudo make install`, same behaviour.

At the moment it requires a arch based Distro and Hyprland. Everything else comes in as a package dependency.
Support for other WMs is on the way.

<br>
<br>


## Features

### Bar

<table><tr><td width="33%"><img src="docs/img/bar-modules.png" alt="Bar with modules"></td><td width="33%"><img src="docs/img/bar-flyout.png" alt="A module flyout"></td><td width="33%"><img src="docs/img/bar-groups.png" alt="A module group"></td></tr></table>

Modules are placed per edge and per zone, dragged into position in the settings rather than written
into a config file. Each one carries its own font, colour and size, and any of them can be collapsed
into a group that opens as a single flyout. Menus grow out of the bar itself instead of appearing
next to it.

**Time & status**
- **Clock** — configurable time and date format
- **Performance** — CPU, memory, GPU; opens btop in a dropdown
- **Battery** — with a low warning, and the charge of mouse and keyboard
- **Temperature** — Celsius or Fahrenheit
- **Updates** — pending package count, click to refresh

**Connectivity**
- **Network** — Wi-Fi list, connect and forget, SSID on the bar
- **VPN** — connection state and switching
- **Bluetooth** — devices, pairing, rename, grouping
- **Tray** — StatusNotifierItems, with the shell's own context menus

**Media & sound**
- **Volume** — output and input, per-application streams
- **Media** — title, transport, album art as a spinning record, spectrum backdrop

**Workspace**
- **Workspaces** — per monitor, with numbers on the active one
- **Submap** — the active Hyprland submap
- **Tasks** — open windows
- **Layout** — the current layout, switchable from the bar

**System & personal**
- **Notifications** — unread count, opens the notification centre
- **User** — avatar and name, session actions
- **Wallpaper** — the wallpaper quick menu
- **Velumeron icon** — the settings menu
- **Groups** — your own named collection of the modules above, in one pill


### Shell

<table><tr><td width="33%"><img src="docs/img/shell-notifications.png" alt="Notification centre"></td><td width="33%"><img src="docs/img/shell-osd.png" alt="OSD"></td><td width="33%"><img src="docs/img/shell-lock.png" alt="Lock screen"></td></tr></table>

Notification centre and popups, an OSD for volume and brightness, a taskbar and the lock screen —
all native Quickshell surfaces, following the same palette and the same motion. The lock screen
authenticates through PAM directly; there is no hyprlock underneath it, and it can be run on its
own next to a setup that is otherwise not Velumeron.

The first start is covered too: a splash holds the screen while the shell comes up, and the setup
wizard walks through workspaces, wallpaper, apps and avatar.


### Launcher

<table><tr><td width="33%"><img src="docs/img/launcher-apps.png" alt="App search"></td><td width="33%"><img src="docs/img/launcher-files.png" alt="File mode"></td><td width="33%"><img src="docs/img/launcher-commands.png" alt="Keybind help"></td></tr></table>

Applications by default, with fuzzy or substring matching. Prefixes switch mode: `>` runs a
command, `!f` browses files with thumbnails, `!v` calls shell actions, `!k` searches your keybinds.
One window, four jobs, instead of four separate tools.


### Window management

<table><tr><td width="33%"><img src="docs/img/window-tags.png" alt="Window tags"></td><td width="33%"><img src="docs/img/zones.png" alt="Snap zones"></td><td width="33%"><img src="docs/img/window-switcher.png" alt="Window switcher"></td></tr></table>

- **Window tags** — a label floating on each window, so a screen full of terminals stops being a
  guessing game. Fades with cursor distance, per-window text you set yourself.
- **Snap zones** — your own layouts for floating windows: drag a window, drop it into a zone, it
  takes that shape. Zones are drawn in the settings, per monitor.
- **Window switcher** — Alt-Tab across workspaces with previews, and a second switcher for
  Hyprland layouts.
- **Layouts** — named tiling layouts on top of Hyprland's dispatchers, switchable from the bar or
  a keystroke.
- **Window rules** — size, position, workspace, floating, opacity per application, written in the
  GUI instead of in `windowrulev2` lines.


### Overlays

<table><tr><td width="33%"><img src="docs/img/clipboard.png" alt="Clipboard history"></td><td width="33%"><img src="docs/img/keybinds.png" alt="Keybind cheatsheet"></td><td width="33%"><img src="docs/img/session.png" alt="Session menu"></td></tr></table>

- **Clipboard history** — searchable, with image entries, backed by clipvault.
- **Keybind cheatsheet** — every binding, grouped and searchable, generated from the config you
  actually run rather than from a list someone keeps up to date by hand.
- **Session menu** — lock, log out, suspend, reboot, shut down.
- **Hot corners** — an action per corner, with its own dwell time, and any of them can stay empty.


### Settings, not dotfiles

<table><tr><td width="33%"><img src="docs/img/settings-bar.png" alt="Bar layout"></td><td width="33%"><img src="docs/img/settings-style.png" alt="Style and colours"></td><td width="33%"><img src="docs/img/settings-dashboard.png" alt="The dashboard"></td></tr></table>

Everything the desktop can do is configurable in a GUI: bar layout and per-module options, style
and templates, monitors by drag-and-drop, workspaces, window rules, zones, keybinds, autostart,
peripherals. It writes the same files you could edit by hand. The home page is a dashboard you
arrange yourself from tiles — sliders, toggles, media, glances.


### Wallpaper engine

<table><tr><td width="33%"><img src="docs/img/wallpaper-picker.png" alt="Picker"></td><td width="33%"><img src="docs/img/wallpaper-live.png" alt="Live wallpaper"></td><td width="33%"><img src="docs/img/theming-apps.png" alt="Apps in the palette"></td></tr></table>

Per monitor, static images or live video, with GPU transitions between them — driven by a
libmpv→QtQuick plugin that builds itself on first launch. Whatever is behind you also decides the
colours: wallust derives a palette and it lands everywhere at once, shell, GTK, Qt, kitty, fish and
the mouse cursor, live and without a restart.


### Calendar & tasks

<table><tr><td width="33%"><img src="docs/img/calendar-month.png" alt="Month"></td><td width="33%"><img src="docs/img/calendar-day.png" alt="Day grid"></td><td width="33%"><img src="docs/img/calendar-tasks.png" alt="Task board"></td></tr></table>

A real CalDAV client, not a month printout: events are created and edited in place, the day grid
puts them on a timeline, and tasks live on a board next to them.

Nothing is built in — you point it at your own server. Any CalDAV account works (Nextcloud among
them); credentials stay in a file only your user can read. Vikunja is separate: it comes in over
its REST API, because CalDAV has no notion of a project tree or of subtasks. Both feed one model,
so a Vikunja project and a CalDAV task list sit next to each other on the same board.

Without an account you get a plain month view — events and tasks live on your server, there is no
local store yet.

Tasks and notes on the desktop are [Disponera](https://github.com/vredix-openvuture/disponera),
a separate application from the same workshop. It reads the very same caches, so the shell and the
app never disagree about what is done.


### Boot themes

<table><tr><td width="33%"><img src="docs/img/boot-plymouth.png" alt="Plymouth"></td><td width="33%"><img src="docs/img/boot-grub.png" alt="GRUB"></td><td width="33%"><img src="docs/img/boot-sddm.png" alt="SDDM"></td></tr></table>

Built in support for grub- / plymouth- / sddm-themes.
Choose your style inside the menu. <br>
(Coming with a own color and wallpaper aware velumeron-theme)

## Roadmap

Planned, in rough order of how much of it already exists:

- **Other Wayland compositors.** The shell is layer-shell and compositor-neutral already; what is
  Hyprland-specific is the config layer and the window/workspace calls. Those move behind one
  abstraction, then Sway (i3 IPC) and niri (niri IPC) follow as backends.
- **Workspace 1 as a desktop dashboard.** Widgets that live above the wallpaper and below the
  windows — clock, disk, media — instead of only inside the settings menu.
- **Clock and timer** next to the calendar, and a deeper Disponera integration.
- **The lock screen's big look** — the current one is deliberately plain.
- **Standalone components.** Running single pieces (lock screen, notifications, OSD) next to
  someone else's setup, without the rest of Velumeron.

Changes: [CHANGELOG.md](CHANGELOG.md) · Uninstall: `velumeron-purge-goodby` (dry run by default)



MIT licensed.

---

<br>
<br>

<a href="https://ko-fi.com/openvuture"><img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Support me" height="30"></a>

<a href="https://openvuture.com"><img src="assets/icons/openvuture-button.svg" alt="OpenVuture" height="30"></a> <a href="https://openvuture.shop"><img src="assets/icons/openvuture-shop-button.svg" alt="OpenVuture Shop" height="30"></a>

