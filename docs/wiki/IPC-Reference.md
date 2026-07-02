# IPC Reference

Every overlay can be driven from keybinds or scripts:

```bash
qs -p "$VELUMERON_DIR/quickshell" ipc call <target> <function>
```

| Target | Functions | Notes |
| --- | --- | --- |
| `menu` | `toggle` `open` `close` | The settings menu (corner menu) |
| `launcher` | `toggle` `open` `close` | Application launcher |
| `clipboard` | `toggle` `open` `close` | Clipboard history |
| `window` | `open` `toggle` `close` | Window switcher (`open` while open advances) |
| `session` | `toggle` `open` `close` | Session / power menu |
| `notify` | `toggle` `open` `close` `dnd` | Notification centre · do-not-disturb |
| `keybind` | `all` `window` `apps` `system` `close` | Keybind cheatsheet (each toggles its context) |
| `osd` | `volume` · `brightness <percent>` | Show the volume / brightness OSD |
| `flyout` | `volume` `mpris` `calendar` `close` | Bar flyouts at their last-known anchor |
| `wallpaper` | `toggle` `open` `close` | Wallpaper quick menu (grows from the module / configured position) |
| `btop` | `toggle` `close` | btop dropdown terminal |
| `zones` | `open` `close` | FancyZones overlay (normally driven by the compositor) |

> Function names `show`/`hide` are avoided by convention: `qs ipc call <target> show` collides
> with qs's built-in target introspection.

## Keybind examples (hypr.lua)

```lua
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("qs -p " .. VTL_DIR .. "/quickshell ipc call launcher toggle"))
hl.bind("SUPER + B",     hl.dsp.exec_cmd("qs -p " .. VTL_DIR .. "/quickshell ipc call btop toggle"))
```

## Compositor-side notes

This Hyprland build runs the **hypr.lua** config runtime:

- `hyprctl dispatch '<lua>'` — the argument is Lua, e.g.
  `hyprctl dispatch 'hl.dsp.exec_cmd([[kitty]])'`. Classic dispatcher syntax does **not** work.
- `hyprctl keyword` is unavailable — dynamic rules go through
  `hyprctl eval 'hl.window_rule({ … })'` (idempotent by `name`).
- Window operations on a specific window:
  `hyprctl eval 'for _,w in ipairs(hl.get_windows()) do if w.class=="x" then hl.dispatch(hl.dsp.window.move({window=w, x=0, y=0, exact=true})) end end'`
- Read-only JSON queries (`hyprctl clients -j`, `monitors -j`, `getoption`) work as usual.
- Never call `hyprctl` from *inside* compositor Lua (config modules, bind handlers) — it
  deadlocks the compositor. Pre-share data through files instead (see Zones for the pattern).
