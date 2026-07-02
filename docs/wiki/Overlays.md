# Overlays

Everything that pops up over your windows. All of these are per-screen layer surfaces rendered by
the shell — no external daemons (no swaync, no rofi).

## OSD (Settings → OSD)

Volume / brightness / workspace banners. Placement on a 9-cell grid, float or dock style,
duration, size, and per-kind display options (bar and/or value; device name). Triggered by the
`osd` IPC (wired to the volume/brightness scripts).

## Notifications (Settings → Notifications)

The shell owns `org.freedesktop.Notifications` (don't run another daemon). Toasts pop in a
configurable corner (dock or float style, same-app grouping); the **notification centre** grows
out of the bell module and keeps history. Do-not-disturb via `qs … ipc call notify dnd`.

## Application launcher — `Super + Space`

List or grid, docked to a bar edge / standalone / fullscreen app grid; size, rows/columns and
backdrop blur in Settings → Launcher.

## Clipboard history — `Super + V`

Searchable clipvault history over a dimmed backdrop; `Enter`/click copies back. Width, rows, dim
and optional backdrop blur in **Settings → OSD → Clipboard history**. Requires the
`wl-paste --watch clipvault store` autostart.

## Window switcher — `Super + Tab`

Alt-Tab style overlay with previews; grabs the keyboard while open.

## Session menu — `Super + Ctrl + Q`

Lock · Suspend · Logout · Reboot · Shutdown — the same actions as the User module's glide.

## Keybind cheatsheet

`qs … ipc call keybind all` (or `window` / `apps` / `system` for a single submap).

## Taskbar (Settings → Taskbar)

A strip of open windows (click to focus): position on the 9-grid, dock/float, always/hover
visibility, scope (monitor / workspace / all), labels, icon size, and optional space reservation
("like bar"). Per-monitor on/off overrides.

## Window tags (Settings → Window tags)

A small name chip on the edge/corner of every window, coloured like the window border. Fades out
when the cursor approaches, and hides while another window covers its spot. Content (title/app),
position, size and max width are configurable.

## Hot corners (Settings → Corners)

Push the cursor into a corner or edge-centre and hold: fires an action (open menu, launcher,
overview, custom command …). Zones, dwell time and sizes are configurable, optionally per monitor.

## btop dropdown

Right-click the **Performance** module (or `qs … ipc call btop toggle`): a kitty window running
btop drops out of the bar — themed live from the current wallust palette, pinned across
workspaces. Size via the Performance module's gear. Uses its own btop profile
(`~/.config/velumeron/btop/`) — your personal btop config is untouched.
