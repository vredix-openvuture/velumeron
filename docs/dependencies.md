# Velumeron — Dependencies

Complete list of everything required for this config to work.

---

## Compositor & Core

| Package | Purpose |
|---|---|
| `hyprland` | Wayland compositor |
| `hypridle` | Idle / timeout daemon |
| `hyprlock` | Lock screen |
| `hyprpolkitagent` | PolicyKit agent |
| `xdg-desktop-portal-hyprland` | Wayland portal (file picker, screenshots, …) |

---

## Bar, Launcher & Notifications

| Package | Purpose |
|---|---|
| `waybar` | Status bar |
| `rofi-wayland` | App launcher & session menu |
| `swaync` | Notification daemon |
| `cava` | Audio visualizer (waybar cava module) |
| `hypremoji` (AUR) | Emoji picker |

---

## Terminal

| Package | Purpose |
|---|---|
| `kitty` | GPU-accelerated terminal (default) |

---

## Autostart & System Daemons

| Package | Purpose |
|---|---|
| `awww` | Animated wallpaper daemon (smooth transitions) |
| `nm-applet` | NetworkManager system tray |
| `gnome-keyring` | Secret / keyring storage |
| `clipvault` | Clipboard manager (wl-paste integration) |
| `wl-clipboard` | `wl-copy` / `wl-paste` |
| `btop` | System monitor (workspace 99 autostart) |

---

## Wallpaper & Theming

| Package | Purpose |
|---|---|
| `wallust` | Generate color schemes from wallpapers |
| `mpvpaper` | Video wallpapers |
| `imagemagick` | Thumbnail generation (`magick`, `identify`) |
| `ffmpeg` | Video wallpaper info (`ffprobe`) |
| `python-pywalfox` | Sync wallust colors to Firefox |

---

## Audio & Media

| Package | Purpose |
|---|---|
| `pipewire` | Audio server |
| `pipewire-pulse` | PulseAudio compatibility layer |
| `wireplumber` | PipeWire session manager |
| `playerctl` | Media player control (play/pause/next/prev) |
| `pulsemixer` | Volume mixer (waybar click action) |

---

## Screenshot & Screen Tools

| Package | Purpose |
|---|---|
| `grim` | Screenshot (hyprlock preview, general use) |
| `hyprshot` | Hyprland screenshot utility |

---

## System Utilities

| Package | Purpose |
|---|---|
| `jq` | JSON processing (scripts) |
| `socat` | Hyprland IPC socket relay |
| `power-profiles-daemon` | Power profile switching |
| `gamemode` | Game Mode daemon (`gamemoded`) |
| `lm_sensors` | CPU/GPU temperature monitoring |
| `ddcutil` | Monitor brightness via DDC-CI |
| `libnotify` | `notify-send` for desktop notifications |
| `xdg-utils` | `xdg-open` |

---

## Bluetooth

| Package | Purpose |
|---|---|
| `bluez` | Bluetooth stack |
| `bluez-utils` | `bluetoothctl` |
| `bluetui` | TUI Bluetooth controller (waybar click) |

---

## GUI Settings App

| Package | Purpose |
|---|---|
| `gtk4` | GTK4 toolkit |
| `libadwaita` | Adwaita widgets / style |
| `python-gobject` | Python GTK4 bindings |
| `python` | Python 3.x runtime |
| `gtk4-layer-shell` | Wayland layer shell protocol (slide-in panel) |

---

## Fonts

| Font | Used in |
|---|---|
| **FantasqueSansM Nerd Font** | Waybar, Rofi, Swaync (main UI font) |
| **Atomic Age** | Hyprlock — clock time display |
| **Audiowide** | Waybar clock module |

> Install Nerd Fonts from `nerd-fonts` (AUR) or `ttf-fantasque-sans-mono-nerd` specifically.

---

## Icons & Cursors

| Package | Purpose |
|---|---|
| `breeze-icons` | Tab icons in the Settings GUI |
| `breeze` | Cursor theme (`breeze_cursors`) |

---

## Optional / Feature-Specific

| Package | Purpose |
|---|---|
| `fish` | Default shell (set in user_settings) |
| `tmux` | Terminal multiplexer |
| `fastfetch` | System info display |
| `kvantum` | Qt style override for Qt6 apps |
| `qt5ct` / `qt6ct` | Qt platform theme — carries the wallust palette to Qt apps (Style → App theming) |
| `adw-gtk-theme` | GTK3 port of Adwaita — the GTK app theme (Style → App theming, dark/light) |
| `zenity` | Native file-picker dialogs (wallpaper folders, avatar page) |
| `brightnessctl` | Laptop panel brightness (brightness keys; ddcutil covers external monitors) |
| `wl-clipboard` / `clipvault` | Clipboard watcher + history store (clipboard menu) — clipvault is AUR |
| `ffmpeg` | First-frame thumbnails for live (video) wallpapers |
| `libnotify` | `notify-send` used by several scripts |
| `syncthing` | File sync daemon (user-defined autostart) |
| `nextcloud-client` | Cloud sync (user-defined autostart) |
| `openrgb` | RGB lighting control (user-defined autostart) |
