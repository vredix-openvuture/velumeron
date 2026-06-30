# Wallust (Color Generation)

Wallust generates a color palette from the current wallpaper and writes it to all themed config files via templates.

## Config location

`~/.config/velumeron/wallust/wallust.toml` — controls backend, palette algorithm, saturation, and template targets.

## Templates

| Source file | Target |
|---|---|
| `colors.lua` | `hypr.lua/colors.lua` (Hyprland colors) |
| `colors-kitty.conf` | `kitty/colors.conf` |
| `colors-rofi.conf` | `rofi/assets/colors.rasi` |
| `colors_gtk.css` | `assets/colors_gtk.css` |
| `gtk3.css` | `~/.config/gtk-3.0/wallust.css` |
| `pywal-colors` / `.json` | `~/.cache/wal/colors*` (Firefox via pywalfox) |
| `starship-palette.toml` | `~/.cache/wallust/` |
| `vscode.json` / `vscode` | `~/.cache/wallust/colors*` |

## Hooks (run after every `wallust run`)

1. `hyprland_lua-colors.sh` — converts hex → rgb in `colors.lua`, then `hyprctl reload`
2. `pywalfox update` — updates Firefox colors
3. Restart `swaync`
4. `pkill -SIGUSR2 waybar` — hot-reload Waybar CSS

## Color mode

Controlled by `wallust/color-mode`:
- `auto` — wallust generates colors from the wallpaper image
- `fixed:<filename.json>` — wallust loads a pre-made scheme from `wallust/fixed_colors/`

Change via the GUI (Colors tab) or by editing the file directly.

## Adding a fixed scheme

Drop a `.json` file into `wallust/fixed_colors/`. The GUI picks it up automatically after Refresh.

The format is a standard pywal/wallust color JSON:
```json
{
  "wallpaper": "path",
  "colors": {
    "color0": "#1a1a2e",
    "color1": "#e94560",
    ...
  }
}
```
