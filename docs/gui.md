# Settings GUI

A GTK4/Adwaita settings panel for the most common Vutureland configuration tasks.

## Running

```bash
python3 ~/.config/vutureland/gui/main.py
```

Or via the menu button in Waybar.

## Tabs

| Tab | Description |
|---|---|
| **Hyprland** | Monitors, keys, cursor, autostart, window rules |
| **Waybar** | Drag-and-drop bar slot editor (per-monitor, per-bar) |
| **Wallpaper** | Thumbnail browser; import and apply wallpapers |
| **Colors** | Wallust mode toggle (auto vs. fixed scheme) |

## Structure

```
gui/
├── main.py          # Adw.Application entry point, CSS loading
├── constants.py     # All shared paths and constants
├── style.css        # Custom CSS classes
├── models/
│   ├── hyprland.py  # Parse/write user_settings.lua sections
│   ├── wallpaper.py # Scan wallpaper directories, generate thumbnails
│   └── waybar.py    # Scan output/ bars, read/write groups.json, scan modules
└── pages/
    ├── hyprland.py  # HyprlandPage widget
    ├── wallpaper.py # WallpaperPage widget
    ├── wallust.py   # WallustPage widget
    └── waybar.py    # WaybarPage widget with BarZone drag-and-drop
```

## Waybar editor drag-and-drop

- Drag a chip from the **Module Palette** (right panel) onto a **Left / Center / Right** zone to add it.
- Drag a chip from one zone to another to move it.
- Click **×** on a chip to remove it.
- Click **Apply & Restart Waybar** to save and hot-restart.

The palette only shows modules matching the bar's orientation (horizontal modules for top/bottom bars, vertical modules for left/right bars).

## Dependencies

- `python-gobject`
- `gtk4`
- `libadwaita`
