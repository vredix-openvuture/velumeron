# Bar Modules

Add, arrange and remove modules in **Settings → Bar → Modules**. Most modules have a **gear**
(per-module customization): font, size, colour role and module-specific options — stored under
`module_settings.<module>` in settings.json.

## Modules

| Module | What it does | Interactions |
| --- | --- | --- |
| **Clock** | Time + date (formats via gear) | Click → [calendar & tasks menu](Calendar-and-Tasks.md); shows a dot when tasks are due |
| **Performance** | Power-profile glyph; hover glides CPU/RAM/GPU stats out of the bar | Left click cycles power profile · right click drops a themed **btop** terminal (size via gear) |
| **Updates** | Count of pending updates (repo via `checkupdates`, AUR via paru/yay, optional flatpak); hidden when up to date | Left click opens a terminal with your update command · right click re-checks. Cadence/sources/command via gear |
| **Workspaces** | Workspace dots/numbers per monitor | Click to switch |
| **Tasks** | Open windows of this monitor | Click focuses |
| **Submap** | Active keybind submap indicator | — |
| **Media (mpris)** | Prev/play/next + scrolling title | Click title → player flyout; wheel = next/prev |
| **Volume** | Output volume | Click → device flyout (outputs/inputs, per-device sliders); wheel steps volume |
| **Network** | Connection status, hover glides throughput | Click → network flyout |
| **Bluetooth** | Connected devices (hover glide) | Click → BT flyout (pair, rename, groups) |
| **VPN** | Active VPN name | — |
| **Battery** | Charge percent, low-threshold warning via gear | — |
| **Temperature** | CPU temp (°C/°F via gear) | — |
| **Notifications (notiftray)** | Bell + unread count; hover glides tray icons | Click → notification centre |
| **Tray** | System tray icons | — |
| **User** | Username; hover glides session actions (lock/suspend/…) | — |
| **Wallpaper** | Opens the wallpaper quick menu | Click |
| **Vuture icon** | The main menu button | Click → settings menu |

## Flyouts vs glides

- **Glides** slide a small pill out of the bar on hover (volume %, performance stats, tray icons,
  network throughput, session actions).
- **Flyouts** are click-opened panels that dock into the bar with the same grow-from-corner
  transition as the settings menu (volume routing, media player, network, bluetooth, calendar,
  wallpaper quick menu).

Only one flyout is open at a time; `Escape` or a click outside closes it.
