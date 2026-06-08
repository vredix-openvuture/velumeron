# Vutureland — Architecture & Engineering Reference

This is the single, all-encompassing technical reference for Vutureland: how the
project is laid out, how every component is wired, how data (especially colours)
flows, the development workflow, and a running change log.

It is a **living document** — every change to the project should be reflected
here (see [Change Log](#change-log) at the bottom). Keep it accurate; it is the
basis for the public docs.

> Topic-specific docs live alongside this file: [dependencies](dependencies.md),
> [gui](gui.md), [hyprland](hyprland.md), [wallpaper](wallpaper.md),
> [wallust](wallust.md), [waybar](waybar.md). This file is the overview that ties
> them together.

---

## 1. The two-tier model (the single most important concept)

Vutureland always runs against **two** locations:

| Role | Variable | On a client (AUR) | On the dev box |
|------|----------|-------------------|----------------|
| **Source / package** (read-only templates, scripts, assets) | `VUTURELAND_DIR` | `/usr/share/vutureland` | the git repo, e.g. `~/DEV/vutureland` |
| **User runtime** (synced templates + generated state + wallust output) | `VUTURELAND_USER_DIR` | `~/.config/vutureland` | `~/.config/vutureland` |

**Golden rule:** the source is the *base* you edit; the user dir is what
everything *operational* reads and writes at runtime. Nothing operational should
read `VUTURELAND_DIR` directly for files that wallust rewrites or that the user
customises — those must come from `VUTURELAND_USER_DIR`, otherwise live colours
and edits won't take effect.

Why it matters: many config files use a **relative** `@import` of the palette
(e.g. `@import "../../../../../assets/colors_gtk.css"`). GTK/rofi resolve a
relative import against the **importing file's own location**. So a file loaded
from the package dir imports the *static packaged* palette, while the same file
loaded from the user dir imports the *wallust-updated* palette. Loading config
from the wrong tier is the root cause of the whole "colours don't update" class
of bugs (see Change Log).

On the dev box `VUTURELAND_DIR` points at the repo so you get a fast edit loop
(edit → `--sync` → test) without rebuilding a package. **Do not install the AUR
package on the dev box** — it would move `VUTURELAND_DIR` to `/usr/share` and your
repo edits would stop taking effect until a rebuild.

---

## 2. Repository / source layout

```
vutureland/
├── welcome_to_vutureland.sh     # setup + --sync (the installer/updater)
├── bin/vutureland               # settings-panel launcher (symlinked to ~/.local/bin)
├── assets/
│   ├── scripts/                 # runtime scripts (launch-*, wallpaper-set, lib/env.sh, …)
│   ├── wallpaper/               # default wallpapers (horizontal/, vertical/, hyprlock/, sets.json)
│   ├── icons/                   # app/brand icons
│   └── colors_gtk.css           # tracked wallust *fallback* (real palette lives in user dir)
├── hypr.lua/                    # Hyprland config (Lua), hyprlock themes, hypridle, colors.lua
│   ├── hyprland.lua, modules/*.lua
│   ├── hyprlock-themes/*.conf   # {{mon1}}/{{mon2}} placeholder themes
│   ├── hyprlock.conf            # default active-lock template (placeholders, NOT device names)
│   └── user_settings.lua        # device-specific, GITIGNORED
├── waybar-modular/
│   ├── config/miboro/base/      # bar shells (bar.css/.config.json per position)
│   ├── config/miboro/modules/horizontal/<module>/{config.json,style.css}
│   └── output/                  # GENERATED per machine, gitignored, never synced
├── rofi/                        # *.rasi menus + assets/*.sh launchers + assets/colors.rasi (wallust)
├── swaync/                      # config.json + style.css
├── kitty/, fastfetch/, gamemode/
├── wallust/
│   ├── wallust.toml             # template→dest mapping + [hooks]
│   └── templates/               # the *source* palette templates (edit colours here)
├── gui/                         # GTK4/Adwaita settings panel (see §8)
└── docs/                        # this file + topic docs
```

Device-specific / generated files that are **gitignored** (never commit your
machine's copy): `hypr.lua/user_settings.lua`, `gui/settings.json`,
`waybar-modular/output/`, and the wallust *fallback* outputs are tracked with
default values only (`assets/colors_gtk.css`, `hypr.lua/colors.lua`,
`kitty/colors.conf`, `rofi/assets/colors.rasi`).

---

## 3. Setup & sync — `welcome_to_vutureland.sh`

Two modes:

- **Full run** (no args): first-time interactive setup.
- **`--sync`**: refresh the user dir from the source and reload everything. This
  is the everyday "apply my changes" command on the dev box, and what a client
  effectively does after a package update.

`sync_templates()` does, in order:
1. Drops stale top-level symlinks in the user dir (rofi/kitty/swaync/assets/…).
2. Copies the `kitty rofi swaync hypr.lua waybar-modular` subtrees → user dir,
   **skipping**: wallust outputs (never overwrite live colours) and
   `waybar-modular/output/` (generated per machine; a dev tree may carry stale
   output that would pin bars to old paths/colours).
3. Symlinks `assets/{wallpaper,icons,scripts}` from the source into the user dir
   (read-only assets referenced by absolute `~/.config/vutureland/assets/...`
   paths).
4. Seeds wallust output fallbacks as **real files** (so wallust can write them).
5. Wires `~/.config/hypr/{hypridle,hyprlock}.conf` as symlinks to the user dir —
   re-pointing even if a plain file (manual `cp` / old install) sits there.
6. Writes `~/.config/swaync/style.css` as a **real file** with the palette
   `@import` rewritten to an **absolute** path (GTK4 resolves swaync's relative
   import against the symlinked default path, which would otherwise miss the
   palette). config.json is written by `launch-swaync.sh`.
7. Wires the GTK theme (adw-gtk3-dark + dark color-scheme; `gtk.css` imports
   `wallust.css`).
8. Installs the bundled fonts (`assets/fonts/*.ttf` → `~/.local/share/fonts/
   vutureland/`, then `fc-cache`). Per-user, no root; idempotent (only copies
   new/updated files). These are the fonts the configs require — `FantasqueSansM
   Nerd Font` (waybar/swaync/rofi), `Atomic Age` (hyprlock), `Audiowide`.

`apply_default_bar(monitor)` generates the default top bar (see §6). The `--sync`
path then regenerates bars, runs `hyprctl reload`, restarts waybar + swaync, and
restarts the settings panel.

---

## 4. The colour pipeline (wallust)

```
wallpaper change ──▶ wallust run/cs (config-dir = $VUTURELAND_DIR/wallust)
                         │  uses wallust/templates/*  + wallust.toml mapping
                         ▼
       writes palette to many destinations, e.g.:
         ~/.config/vutureland/assets/colors_gtk.css   (GTK/waybar/swaync)
         ~/.config/vutureland/rofi/assets/colors.rasi (rofi)
         ~/.config/vutureland/kitty/colors.conf       (kitty)
         ~/.config/vutureland/hypr.lua/colors.lua     (hyprland)
         ~/.config/gtk-3.0/wallust.css, gtk-4.0/...   (GTK apps)
                         │
                         ▼  [hooks] in wallust.toml + wallpaper-set.sh
         hyprctl reload · pywalfox · swaync restart · waybar full restart · gtk reload
```

- **Modes:** `auto` (derive from wallpaper) or `fixed:<scheme>` (from
  `wallust/fixed_colors/*.json`), stored in `~/.config/vutureland/wallust/color-mode`.
- **Defined colour names** (`wallust/templates/colors_gtk.css`): `color0`–`15`,
  `foreground/background/cursor`, and semantic aliases `bg-primary/element/
  secondary/active/hover`, `bo-normal/active`, `fg-primary/muted/urgent/bright`.
- **Consumers** import these by name. Because the imports are relative, the
  consuming file **must be loaded from the user dir** (see §1).
- **Refresh requires a full restart, not SIGUSR2:** waybar's palette lives in an
  `@import`ed file; `SIGUSR2` only reloads the top-level style.css and misses it.
  Therefore waybar is fully restarted on colour change (wallust `waybar_update`
  hook + `wallpaper-set.sh`; the wallust GUI page also does a full restart).

**Known gap:** some waybar module styles reference `@fg-active`, `@fg-hover`,
`@fg-secondary`, which are **not** defined in the palette yet (they fall back).
Add them in `wallust/templates/colors_gtk.css` (and the tracked fallback
`assets/colors_gtk.css`) if those states need exact theming — do **not** edit the
generated `~/.config/.../colors_gtk.css`, it is overwritten on every change.

---

## 5. Hyprland

Lua config in `hypr.lua/` (`hyprland.lua` + `modules/*.lua`). `colors.lua` is a
wallust output. `user_settings.lua` is device-specific (monitor names etc.) and
gitignored. See [hyprland.md](hyprland.md).

---

## 6. Waybar

Fully modular. Source shells in `waybar-modular/config/miboro/base/`, modules in
`…/modules/horizontal/<module>/{config.json,style.css}`.

- **Default bar:** `apply_default_bar` writes
  `~/.config/vutureland/waybar-modular/output/miboro/bar/top/<monitor>/{config.json,
  groups.json,style.css}`. Layout — left: `clock · sep · performance-drawer · sep ·
  interactive-user`; centre: `workspaces · submap`; right: `cava · audio-drawer ·
  sep · tray-drawer · battery` (battery only on devices with one). Drawers pull in
  their child module configs.
- **Idempotent refresh:** `apply_default_bar` only (re)writes a bar if there is
  none, it points at the read-only package dir, or its module layout matches a
  layout Vutureland has shipped as a default (`_default_bar_layouts`). A
  user-customised bar is left alone.
- **Loading:** `launch-waybar.sh` finds every `output/**/config.json`, merges
  them into `/tmp/waybar-merged-config.json` + `/tmp/waybar-merged-style.css`, and
  runs `waybar -c … -s …`. Only *applied* bars (those with a `config.json`) load;
  auto-init scaffolding leaves only `groups.json`.
- **Colours:** each bar's `style.css` imports the user-dir `bar.css`, which imports
  `../../../../../assets/colors_gtk.css` (→ user-dir wallust palette). Both the
  shell `apply_default_bar` and the GUI generate these paths from
  `VUTURELAND_USER_DIR` so the relative palette import always resolves live.

See [waybar.md](waybar.md).

---

## 7. Hyprlock (lock screen)

- **Themes:** `hypr.lua/hyprlock-themes/*.conf` use `{{mon1}}`/`{{mon2}}`
  placeholders and `~/.config/vutureland/assets/wallpaper/hyprlock/<img>` paths.
- **`assets/scripts/apply-hyprlock-theme.sh <theme>`** is the single writer of the
  active config: it substitutes **this machine's** monitors into the placeholders,
  rewrites image paths to **absolute** package paths (hyprlock 0.9.x does not
  expand `~`), drops any leftover `{{monN}}` background block (fewer monitors than
  the theme expects), writes `~/.config/vutureland/hypr.lua/hyprlock.conf`, and
  records the chosen theme in `…/.hyprlock-theme`.
- **Consumers:** the rofi picker (`rofi/assets/rofi-hyprlock.sh`) and the GUI
  lockscreen page both delegate to that script.
- **Default lock path:** `~/.config/hypr/hyprlock.conf` is a symlink to the user
  file (hyprlock reads the default path).
- **Self-heal:** `launch-hyprlock.sh` regenerates the active config before locking
  if it references none of the current monitors (e.g. a config synced with another
  machine's monitor names) — so clients fix themselves on the next lock.

The packaged `hypr.lua/hyprlock.conf` ships with **placeholders**, never real
monitor names (shipping `DP-2`/`DP-3` once caused clients to show no wallpaper).

---

## 8. Settings GUI (`gui/`)

GTK4/Adwaita panel, `Adw.Application`, gtk4-layer-shell, run as a daemon.

- **Launcher:** `bin/vutureland` (sets `LD_PRELOAD=libgtk4-layer-shell`). Symlinked
  to `~/.local/bin/vutureland`. Flags: `--daemon` (start, kept alive hidden),
  `--toggle` (SIGUSR1 show/hide), `--end` (quit).
- **Restart it:** `vutureland --end; vutureland --daemon & disown` — or just run
  `welcome_to_vutureland.sh --sync`, which restarts it too.
- **Icons:** the panel forces the **Adwaita** icon theme for its own process, so
  it is independent of the user's system icon theme (which may lack freedesktop
  symbolic names and render everything as the broken placeholder). Only Adwaita
  symbolic names may be used in GUI code.
- **Pages** (`gui/pages/`): `home`, `hyprland`, `waybar` (Bar), `wallpaper`
  (Theme, with Sets/Horizontal/Vertical/Colors), `lockscreen` (Power & Lock),
  `notifications`. Models in `gui/models/`. The waybar model resolves all paths
  from `VUTURELAND_USER_DIR`.

See [gui.md](gui.md).

---

## 9. Other consumers

- **swaync:** `~/.config/swaync/{config.json,style.css}` (style.css written with an
  absolute palette import; `launch-swaync.sh` rewrites it on every launch so a
  stale/foreign file self-heals). Started via systemd user unit / D-Bus, so it
  must read the default path.
- **rofi:** menus are launched with their `.rasi` from the **user dir** so
  `@import "./assets/colors.rasi"` resolves to the wallust output. (Launching from
  the package dir would pick up the static packaged palette.)
- **kitty:** `~/.config/vutureland/kitty/` (colors.conf is a wallust output).

---

## 10. Development workflow

```
1. Edit the SOURCE in the repo (~/DEV/vutureland/…)   ← the "base"
2. welcome_to_vutureland.sh --sync                    ← apply to ~/.config/vutureland
3. Test
4. git commit && git push                             ← clients get it via: yay -S vutureland-git
```

- Never edit files under `~/.config/vutureland/` — they are overwritten by `--sync`
  or wallust.
- To change **colours**, edit `wallust/templates/` (not the generated outputs).
- To change the **default bar**, edit `apply_default_bar` and/or the
  `waybar-modular/config/miboro/base|modules` source; a `--sync` only refreshes
  *un-customised* default bars.
- Commit messages: end with the project's `Co-Authored-By` trailer.
- Clients are `vutureland-git` (VCS package); they pick up `main`. `yay -S
  vutureland-git` forces a rebuild from HEAD (plain `-Syu` may not detect new
  commits without `--devel`).

---

## 11. Cross-app theming (designs)

Selecting a waybar **design** also themes hyprland, swaync and the GUI. Each app
keeps a `themes/<design>` file; the current look is shipped as **`miboro`**.

- **Active design record:** `~/.config/vutureland/active-theme` (a file holding
  the name, e.g. `miboro`). Default when absent = `miboro`.
- **Per-app theme files:**
  - `swaync/themes/<design>.css` — `launch-swaync.sh` writes the active one to
    `~/.config/swaync/style.css` (palette `@import` rewritten to absolute).
  - `hypr.lua/themes/<design>.lua` — `hyprland.lua` `dofile`s the active one
    **after** `look_and_feel` (overrides design-specific look). It must **not**
    set `rounding`/`border_size` — those stay user-controlled via the Look and
    Feel page. `miboro.lua` is empty (miboro = the look_and_feel default).
  - `gui/themes/<design>.css` — `main.py` loads the active one into a global
    provider after the base `style.css` (so it wins); `reload_design_theme()`
    restyles it live.
- **Switch:** applying a bar design in the GUI (`waybar._apply_app_theme`) writes
  `active-theme`, restyles the GUI live, and reloads swaync + `hyprctl reload`.
- **Fallback:** a missing per-app theme file is a no-op (the base/default stands),
  so adding a new waybar design never breaks the other apps.

## 12. Known issues / open design decisions

- **Adding wallpapers on clients (copy target).** The panel-dismiss bug is fixed
  (see Change Log `a38b246`), so the Add dialog now opens correctly. But the copy
  target `WALLPAPER_H/WALLPAPER_V` (GUI constants) still points at
  `$VUTURELAND_DIR/assets/wallpaper/...`, i.e. the **read-only package** on
  clients, and the user wallpaper dir is a symlink to it — so the actual copy
  fails on clients (works on the dev box, where the repo is writable). Fix needs a
  user-writable wallpaper location: keep package defaults read-only, add a
  writable per-user wallpaper dir, and have the scanner/thumbnailer/`wallpaper-set`
  read both. (Avoids duplicating the ~43 MB of default wallpapers.) **Decision
  pending.**
- **Dialogs from the layer-shell panel — general rule.** The panel is a fullscreen
  TOP layer-shell window, so *any* secondary window (portal file dialog **or** an
  `Adw.Window` like the set editor) renders under it and the panel's transparent
  overlay swallows its input. The required pattern is: **hide the panel while the
  secondary window is open, restore it on close**; do not make the secondary
  window transient/modal against the panel (a layer-shell surface can't parent
  it). Used by the wallpaper Add dialog (parent `None` + hide/restore) and the
  `SetEditorDialog` (hide panel in `__init__`, restore on `close-request`).
- **`@fg-active` / `@fg-hover` / `@fg-secondary`** are used by waybar modules but
  not defined in the palette (see §4).

---

## Change Log

Newest first. Each entry: what changed, why, and the commit.

### 2026-06-08
- **Cross-app theming (D)** — waybar design selection now also themes hyprland,
  swaync and the GUI via per-app `themes/<design>` files + an `active-theme`
  record. See §11. Current look shipped as `miboro` (no visible change yet).
- **Home: Network & Bluetooth in-panel subpages (C1)** — `nmcli`/`bluetoothctl`,
  Wi-Fi scan/connect (in-row password), VPN toggles, BT connect/disconnect.
- **Home: active waybar style + wallpaper preview (C2)**.
- **Custom wallpaper folders (A2)** — per-client hor/ver paths
  (`gui/settings.json`), resolver in GUI + shell; arbitrary filenames supported;
  custom folder also receives "Add". **Sets are client-side now (A1)** — not
  shipped.
- **GUI polish** — round toggles/sliders (B2); sidebar = window bg + ~10% accent,
  fewer accent blocks (B1).
- **hypremoji** added to dependencies (E).
- Backup before this batch: `~/DEV/vutureland-backup-2026-06-07_2029` (HEAD
  `24739a1`).

### 2026-06-07
- **Hyprland page: Look and Feel category** (`<pending>`). New group with Border
  Radius / Border Size; written to a `LOOKANDFEEL` section in user_settings.lua as
  `lnf_rounding` / `lnf_border_size`, which look_and_feel.lua reads with a fallback
  (`lnf_rounding or 10`, `lnf_border_size or 2`) — unset = hypr.lua default.
  `ensure_lookandfeel_section` adds the section to older user_settings.lua files.
- **Window rules as an in-panel list editor** (`51691ad`). Floating/Opacity rules
  are activatable rows opening a subpage that lists matched apps as plain names
  (+ add, alphabetical); `parse_rule_entries`/`build_rule_pattern` convert
  names↔regex (`kitty` ↔ `.*[Kk]itty.*`). HyprlandPage is now a `Gtk.Box` + stack.
- **Fixed: user_settings section markers kept their "-- " prefix** (`8d52de3`).
  `_write_section` stripped the comment prefix off the END marker, producing
  invalid Lua (`<<<PERIPHERALS-END>>>` without `--`) that broke the config when
  the GUI saved (e.g. the function-key bindings).
- **This document created** — comprehensive architecture reference + living change
  log.
- **Bundled fonts auto-installed on sync** (`<pending>`). `assets/fonts/` now ships
  FantasqueSansM Nerd Font, Atomic Age and Audiowide; `--sync` installs them to
  `~/.local/share/fonts/vutureland/` (per-user, idempotent) so clients render
  correctly without manual font setup. See §3 step 8.
- **In-panel set editor + library image picker** (`f7b7b49`). The set editor was a
  separate `Adw.Window` that couldn't be used under the layer-shell panel. It is
  now an in-panel `Gtk.Stack` view (main ↔ editor ↔ image picker); the picker
  chooses from the existing wallpaper library instead of a file dialog. The picker
  shows Horizontal and Vertical images in separate sections (landscape vs portrait
  thumbnails) divided by a light separator.
- **Set editor usable from the panel** (`805946d`). "New Set"/edit-set was a modal
  `Adw.Window` transient-for the layer-shell panel, so it rendered under the panel
  and couldn't be interacted with. Now the panel hides while the set editor is open
  and restores on close (same pattern as the Add dialog). Generalised rule in §11.
- **Wallpaper "Add" no longer dismisses the panel** (`a38b246`). The portal file
  dialog rendered under the fullscreen TOP layer-shell panel and the click fell
  through to the outside-click catcher, hiding the panel. Now the panel hides while
  the dialog is open (parent `None`) and restores afterwards. (Copy-to-read-only on
  clients remains open — §11.)
- **GUI icons independent of system icon theme** (`b49b5c9`). Every panel icon
  rendered as the broken placeholder because the effective gsettings icon theme
  (Papirus-Dark) lacked many freedesktop symbolic names. The panel now forces the
  Adwaita icon theme for its process and the few Papirus-only names were swapped
  for Adwaita equivalents (Colors→`color-select`, Sets→`view-grid`,
  Horizontal/Vertical→`object-flip-*`, Suspend→`weather-clear-night`).

### 2026-06-06
- **Waybar bars generated from the user dir, not the package** (`337e337`). The GUI
  waybar model built `@import` paths from `VUTURELAND_DIR`; on the dev box that is
  the repo, whose `colors_gtk.css` is the static fallback, so GUI-touched bars
  never followed the theme (the "border colour doesn't update" bug). The model now
  resolves all paths from `VUTURELAND_USER_DIR`, and `sync_templates` no longer
  copies `waybar-modular/output/`. This unified dev and client behaviour.
- **Revert of the "single waybar restart" change** (`adfae3e`). Removing the second
  restart regressed the palette refresh; restored the wallust `waybar_update` hook
  and the `wallpaper-set.sh` poke.
- **rofi menus + wallust-GUI follow the live palette** (`40a176e`). `session-menu`,
  `clipvault`, `bluetooth`, `active-players` loaded their `.rasi` from the package
  dir → static palette; now from the user dir. The wallust settings page restarts
  waybar fully instead of `SIGUSR2`.
- **Hyprlock: absolute image paths + drop unused monitor blocks** (`f5a798d`).
  hyprlock 0.9.x doesn't expand `~`; the active config now uses absolute package
  paths and strips leftover `{{monN}}` blocks (single-monitor machines).
- **Per-device hyprlock, single waybar restart, smarter bar/lock defaults**
  (`7ec452f`). Shipped `hyprlock.conf` with placeholders instead of one machine's
  monitor names; added `apply-hyprlock-theme.sh` + `launch-hyprlock.sh` self-heal;
  `apply_default_bar` only refreshes un-customised defaults; GUI bar page opens on
  the active bar.

### 2026-06-05
- **Repair hyprlock/swaync/waybar theming on clients** (`d15ce57`). Robust symlink
  wiring (replace real files, not just stale symlinks); swaync style.css written
  with an absolute palette import; `pure-black.jpg` path fix; new default bar
  layout; GUI adds new modules at the bottom of a zone.
