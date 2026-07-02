# Settings Reference

All shell settings live in `~/.config/velumeron/gui/settings.json` — flat JSON keys, written by
the settings UI and read live by the shell (`quickshell/VtlConfig.qml`, which is also the
authoritative list). Sensible defaults apply for every missing key.

Per-monitor overrides: with `bar_per_monitor` on, any bar key can be overridden under
`bar_monitors.<monitor>.<key>`; similar maps exist for corners (`corner_monitors`), taskbar
(`taskbar_monitors`), window tags (`window_tags_monitors`), OSD position
(`osd_monitors.<mon>.position`), zone layouts (`fancy_zones_monitors.<mon>`), wallpaper dirs
(`wallpaper_dirs`) and sets.

## Bar

| Key | Default | Meaning |
| --- | --- | --- |
| `bar_mode` | `frame` | `dock` · `float` · `frame` |
| `bar_position` | `top` | Edge for dock/float |
| `bar_edges` | `["top","left"]` | Frame edges |
| `bar_thickness` | `36` | px |
| `bar_float_gap` | `8` | px (float gap / dock end-air) |
| `bar_inner_radius` | `16` | Inner corner radius |
| `bar_module_margin` / `bar_module_spacing` | `12` / `10` | Layout |
| `bar_module_bg` | `none` | `none` · `group` · `module` (+ `…_radius`, `…_opacity`) |
| `bar_icon_size` / `bar_font_size` | `18` / `13` | px |
| `bar_modules_m.<mode>.<edge>.<group>` | — | Module keys per mode/edge/group |
| `bar_per_monitor` | `false` | Enable `bar_monitors.<name>` overrides |
| `bar_opacity_enabled` / `bar_opacity_value` | `false` / `0.88` | Bar translucency |
| `menu_width_pct` / `menu_height_pct` | `20` / `50` | Settings menu size (% of monitor) |
| `module_settings.<module>.<option>` | — | Per-module gear values (font, size, colour, bespoke options) |

## Style

| Key | Default | Meaning |
| --- | --- | --- |
| `ui_style` | `flat` | `flat` · `cards` · `outlined` |
| `colorful_enabled` | `false` | Accent-tinted surfaces (subs: `colorful_bar` `colorful_menus` `colorful_osd`, default on) |
| `transition_style_bar` / `_edge` | `fillet` | Global surface↔bar transition (`fillet` · `straight` · `straight_origin`) |
| `transition_style_<surface>_<ctx>` | `global` | Per-surface override (`menu` `osd` `notify_popup` `notify_center` `flyout`) |
| `opacity_enabled` / `opacity_value` | `false` / `0.88` | Menu translucency |

## OSD & overlays

| Key | Default | Meaning |
| --- | --- | --- |
| `osd_position` | `bottom-center` | 9-grid slot |
| `osd_style` | `float` | `float` · `dock` |
| `osd_duration_ms` / `osd_margin_px` / `osd_width_px` / `osd_height_px` | `1600` / `80` / `320` / `56` | Geometry |
| `osd_volume` / `osd_brightness` / `osd_workspace` | `true` | Per-kind enable (+ `…_display` options) |
| `clipboard_width` / `clipboard_rows` | `640` / `8` | Clipboard history size |
| `clipboard_dim` / `clipboard_blur` | `true` / `false` | Backdrop shade / Hyprland blur |
| `notify_position` | `top-right` | Toast corner (+ `notify_dock`, `notify_group`, `notify_main_monitor_only`) |
| `notify_center_position` | `auto` | Centre placement (+ `…_width`, `…_height`) |

## Launcher

`launcher_position` (`top-center`), `launcher_fullscreen` (false), `launcher_cols` (1 = list),
`launcher_rows` (7), `launcher_width` (560), `launcher_fs_cols` (6), `launcher_blur` (true),
`launcher_dock` (false).

## Wallpaper

| Key | Default | Meaning |
| --- | --- | --- |
| `wallpaper_dir_hor` / `wallpaper_dir_ver` | bundled | Base folders (`wallpaper_dirs.<mon>` per-monitor) |
| `wallpaper_search_subfolders` | `false` | Recurse into subfolders |
| `wallpaper_subfolder_sorting` | `false` | Show one section per subfolder in the pickers |
| `wallpaper_quick_position` | `top-center` | Quick-menu anchor (+ `…_cols` `…_rows` `…_preview`) |
| `wallpaper_auto_mode` | `off` | `off` · `silent` · `show` (+ `…_minutes`, `…_order`) |
| `wallpaper_transition` | `fade` | + `…_ms`, `wallpaper_origin/angle/fade_style/blinds_orient/slide_dir` |
| `wallpaper_sets` | — | Named monitor→file maps |

## Calendar / CalDAV

| Key | Default | Meaning |
| --- | --- | --- |
| `caldav_sync_minutes` | `15` | Refresh cadence |
| `caldav_hidden.<calId>` | — | `true` hides a calendar from the menu |
| `calendar_first_day` | `monday` | `monday` · `sunday` |
| `caldav_default_event_cal` / `caldav_default_todo_cal` | first writable | Quick-add targets |
| `calendar_menu_width` / `calendar_menu_max_height` | `380` / `700` | Menu size (px) |

Accounts (with credentials) live separately in `gui/caldav-accounts.json` (mode 600).

## Zones

`fancy_zones_enabled` (false), `fancy_zones_layout` (`halves`), `fancy_zones_gap` (12),
`fancy_zones_resolved` — the active layout as `"x,y,w,h;…"` fractions (written by the settings
page; shared verbatim with the compositor snap).

## Taskbar · Window tags · Corners

| Area | Keys |
| --- | --- |
| Taskbar | `taskbar_enabled` `taskbar_position` `taskbar_style` `taskbar_visibility` `taskbar_scope` `taskbar_labels` `taskbar_icon_size` `taskbar_margin` `taskbar_layer` `taskbar_monitors.<mon>` |
| Window tags | `window_tags_enabled` `window_tags_position` `window_tags_content` `window_tags_icon` `window_tags_max_width` `window_tags_font_size` |
| Corners | `corner_actions_enabled` `corner_per_monitor` `corner_default_dwell` `corner_size` `corner_edge_length` `corner_zones.<zone>` |

## Tiling layouts

`tiling_layout` (persisted active layout, restored on reload), `custom_layouts` — list of
parametric specs `{name, kind: columns|rows|grid|main_stack, gap, ratio, side}`; Settings →
Layouts generates `~/.config/velumeron/hypr.lua/user_layouts.lua` from them.

## Misc

`bt_aliases.<mac>` / `bt_groups.<mac>` (Bluetooth renames/groups), `low_memory_mode`,
`lockscreen_*` (Settings → Lockscreen).
