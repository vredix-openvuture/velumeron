# Scripts Reference

Everything lives in `assets/scripts/`. All scripts source `lib/env.sh` for `$VELUMERON_DIR`
(package) and `$VELUMERON_USER_DIR` (user data).

| Script | Purpose |
| --- | --- |
| `launch-quickshell.sh` | **The** way to (re)start the shell: builds the mpv plugin if missing, exports `QSG_RHI_BACKEND=opengl` + `QML_IMPORT_PATH`, kills the old instance, launches detached |
| `launch-shell.sh` | Thin wrapper that execs `launch-quickshell.sh` |
| `wallpaper-set.sh` | Applies a wallpaper (per monitor) → `wallpapers.json`, runs wallust (lock-guarded, hang-proof split run), fires the colour hooks |
| `wallpaper-auto.sh` | Timer-driven next-wallpaper pick (order from settings) |
| `wallpaper-random.sh` | Random pick helper |
| `caldav-client.py` | Complete CalDAV client for the calendar menu (discovery, sync → JSON cache, add/complete/delete todos & events). stdlib only. Commands: `load` `sync` `add-account` `remove-account` `add-todo` `toggle-todo` `add-event` `delete-item` |
| `btop-drop.sh` | The btop dropdown: generates a btop theme from the live palette, places + pins a kitty float below the bar via `hyprctl eval`, toggles on re-run |
| `update-check.sh` | Prints `{"repo":N,"aur":N,"flatpak":N,"total":N}` for the Updates module (`--no-aur`, `--no-flatpak`) |
| `volume-up.sh` / `brightness.sh` / `osd-show.sh` | Hardware keys → change + OSD trigger |
| `powermode.sh` | Cycle / query power profiles (Performance module) |
| `apply-theme.sh` / `apply-hyprlock-theme.sh` | Re-apply palette to app configs / hyprlock |
| `hypridle-set.sh` / `launch-hyprlock.sh` | Idle & lock wiring |
| `user-settings-io.py` | **The GUI⇄Lua bridge**: reads/writes the marker sections of `user_settings.lua` as JSON (`get/set/validate/init/reload`). Sections: monitors, workspaces, autostart, quickaccess, peripherals, windowrules, roleapps. Preserves everything outside the target section byte-for-byte; refuses to write on damaged markers; strips + preserves the reserved workspaces (10/90/99/111/112/1111); enforces one default workspace per monitor |
| `onboarding-state.py` | First-run/update decision for the onboarding GUI: compares `VERSION` with `gui/last-seen-version`, slices `CHANGELOG.md`; `state` / `mark-seen` |
| `float-cascade.sh` | Cascade floating windows |
| `build-mpv-plugin.sh` | Builds the libmpv → QtQuick wallpaper plugin (`plugins/Velumeron/Mpv`) |
| `velumeron-config.py` | Legacy settings CLI (predates the in-shell settings) |
| `wallust/` | wallust post-hooks (hex→rgb for Hyprland Lua colours) |

## Data files written at runtime

| File | Writer → Reader |
| --- | --- |
| `$VELUMERON_USER_DIR/gui/settings.json` | Settings UI → whole shell (VtlConfig) |
| `$VELUMERON_USER_DIR/gui/last-seen-version` | onboarding-state.py `mark-seen` → update-report decision |
| `$VELUMERON_USER_DIR/hypr.lua/user_settings.lua` | user-settings-io.py / .setup/hyprland.sh → hypr.lua (device config) |
| `$VELUMERON_USER_DIR/gui/caldav-accounts.json` | caldav-client.py (600) |
| `$VELUMERON_USER_DIR/quickshell/colors.json` | wallust → Colors.qml (live recolour) |
| `$VELUMERON_USER_DIR/quickshell/wallpapers.json` | wallpaper-set.sh → wallpaper engine |
| `$VELUMERON_USER_DIR/hypr.lua/colors.lua` | wallust → hypr.lua (borders) |
| `~/.cache/velumeron/caldav-cache.json` | caldav-client.py → calendar menu |
| `$XDG_RUNTIME_DIR/velumeron-zones.state` | ZonesState.qml → fancyzones.lua (snap geometry) |
| `$XDG_RUNTIME_DIR/vtl-wallust.lock` | wallust runs (flock; non-blocking skip) |
