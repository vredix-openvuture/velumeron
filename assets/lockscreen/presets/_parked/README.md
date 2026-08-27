# Parked lockscreen presets

The six presets Velumeron shipped until 2026-08-27. They are six arrangements of one idea — a
dimmed wallpaper, a small clock, a card — and the verdict was that none of them is memorable.
Only `Console` ships now.

They are parked rather than deleted: `lockscreen-config.py` scans the directory ABOVE this one, so
nothing here is offered in Settings, but every layout they name still exists in
`quickshell/lock/LockContent.qml`. A user whose `lock_layout` is still `band` or `slab` keeps the
look they had — the presets only stop being something new to pick.

To bring one back, move its file up one level. `console-hud.json` is the OLD Console (the hairline
HUD, `lock_layout: hud`); it was renamed so its id cannot collide with the new preset.
