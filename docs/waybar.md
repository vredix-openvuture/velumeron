# Waybar

Vutureland uses a fully modular Waybar setup. Each bar is built individually and combined by `launch-waybar.sh`.

## Directory layout

```
waybar-modular/
├── modules/
│   ├── modules.md          # ordered list of modules + section headers
│   ├── containers.md       # ordered list of group containers
│   └── horizontal/         # one folder per module
│       ├── clock/
│       │   ├── module.md   # metadata: name, alias, description, requires
│       │   ├── config.json # waybar module config
│       │   └── style.css
│       └── ...
├── base/
│   ├── bar/                # base configs: bar, dock, float × top/bottom/left/right
│   └── base-frame/         # multi-bar frame templates (.frame.json)
├── groups/
│   ├── horizontal/         # group container definitions for horizontal bars
│   └── vertical/
└── output/                 # generated per-monitor configs (git-ignored)
    └── {style}/{position}/{monitor}/
        ├── groups.json
        ├── config.json
        └── style.css
```

## Configuring bars

Use the TUI:
```bash
bash ~/.config/vutureland/.setup/waybar.sh
```

Or use the GUI (Waybar tab in `gui/main.py`) for drag-and-drop slot editing.

## Slots

Each bar has three slots: **Left**, **Center**, **Right**. Each slot holds an ordered list of waybar module keys. The TUI and GUI both edit `output/{style}/{position}/{monitor}/groups.json`.

## Adding a module

1. Create a folder under `modules/horizontal/` (or `vertical/`)
2. Add `module.md` with at minimum `name = "..."` and `alias = "..."`
3. Add `config.json` and `style.css`
4. Add the folder name to `modules/modules.md` under the correct section
5. Run the TUI → **Rebuild all** to regenerate output configs

## Frame concept

A `.frame.json` in `base/base-frame/` defines multiple bars for one monitor (e.g. one bar on top + one on the left). The TUI configures each bar's slots sequentially.

## Restarting Waybar

```bash
bash ~/.config/vutureland/assets/scripts/launch-waybar.sh
```
