# Screenshot shot list

The README shows three images per feature. This is the list of what to capture and under which
name — the README already points at these paths, so a file dropped here appears immediately.

**How to capture:** `grim -g "$(slurp)" docs/img/<name>.png` for a region, or `hyprshot -m window`
for a single window. Same wallpaper and the same style preset for all of them, so the strip reads
as one desktop rather than a collection of moods.

**Sizes:** anything between 600 and 1200 px wide. Three sit next to each other in a table, so
similar aspect ratios matter more than resolution — keep a row's three shots roughly equal in
height.

| File | What it shows |
|---|---|
| `bar-modules.png` | The bar itself, with a few modules open enough to read (clock, media, tray, workspaces) |
| `bar-flyout.png` | One module flyout grown out of the bar — volume or network is the clearest |
| `bar-groups.png` | A module group: the collapsed pill and its flyout with the members stacked |
| `shell-notifications.png` | The notification centre with a couple of notifications |
| `shell-osd.png` | The OSD mid-change (volume or brightness) |
| `shell-lock.png` | The lock screen |
| `launcher-apps.png` | The launcher with an app search |
| `launcher-files.png` | The launcher in `!f` file mode, ideally with a thumbnail visible |
| `launcher-commands.png` | The launcher in `>` command or `!k` keybind mode |
| `window-tags.png` | A few windows with their tags visible |
| `zones.png` | The zone overlay while dragging a floating window |
| `window-switcher.png` | Alt-Tab with previews |
| `clipboard.png` | Clipboard history, ideally with an image entry |
| `keybinds.png` | The keybind cheatsheet |
| `session.png` | The session menu |
| `settings-bar.png` | Settings → Bar, module arrangement with the drag chips |
| `settings-style.png` | Settings → Style, the Colours card with the Look presets |
| `settings-dashboard.png` | The settings home dashboard with its tiles |
| `wallpaper-picker.png` | The wallpaper picker with thumbnails |
| `wallpaper-live.png` | A live video wallpaper (a frame where the motion is obvious) |
| `theming-apps.png` | Two or three GTK/Qt apps next to the shell in the same palette |
| `calendar-month.png` | The calendar month view with events |
| `calendar-day.png` | The day/time grid |
| `calendar-tasks.png` | The task board with a project selected |

Optional, if you want the section to have pictures too:

| File | What it shows |
|---|---|
| `boot-plymouth.png` | The Plymouth splash (photograph of the screen is fine) |
| `boot-grub.png` | The GRUB menu |
| `boot-sddm.png` | The SDDM greeter |
