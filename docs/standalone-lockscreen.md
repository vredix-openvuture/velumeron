# Standalone lockscreen (à-la-carte)

Velumeron's native lockscreen can run **on its own**, next to a bar and compositor
config you already have and love. You do not need the velumeron shell, `hypr.lua`,
or any velumeron service for it — just the lockscreen.

It works on any wlroots compositor that speaks the `ext-session-lock` protocol
(Hyprland, sway, niri, …), because the whole lock stack is compositor-agnostic:

- **PAM** authentication from a self-contained confdir (`assets/pam`) — no
  `/etc/pam.d` install, no root (same setuid `unix_chkpwd` path swaylock/hyprlock use).
- **WlSessionLock** — the compositor keeps the screen locked even if the daemon dies.
- **Engagement** via `loginctl` → logind → **hypridle** → an IPC poke. No Hyprland IPC.

## Run it

```sh
# start the (invisible) lock daemon — shows nothing until engaged
assets/scripts/lock-standalone.sh start

# engage it (this is what you wire into hypridle; also handy to test)
assets/scripts/lock-standalone.sh lock
```

Unlock with your login password. Unlocking is **only** possible through PAM — the
IPC socket can start a lock but can never release one.

## Wire it into your own setup

**1. Autostart the daemon** from your compositor config:

```ini
# Hyprland
exec-once = /path/to/velumeron/assets/scripts/lock-standalone.sh start
```
```sh
# sway
exec /path/to/velumeron/assets/scripts/lock-standalone.sh start
```

**2. Point your hypridle at it** (`~/.config/hypr/hypridle.conf`):

```ini
general {
    lock_cmd         = /path/to/velumeron/assets/scripts/lock-standalone.sh lock
    before_sleep_cmd = loginctl lock-session
}
listener {
    timeout    = 300
    on-timeout = loginctl lock-session
}
```

Now every `loginctl lock-session` — from a keybind, the idle timeout, or before
suspend — locks the screen with velumeron's lockscreen. Bind a key to
`loginctl lock-session` for a manual lock.

## Requirements

- `quickshell` (the `qs` binary), `hypridle`, `grim` (pre-lock desktop screenshot),
  and `playerctl` (pause/resume media on lock) in `PATH`.
- **Fonts**: the lockscreen uses *FantasqueSansM Nerd Font*. A full velumeron
  install bundles it; standalone, install it yourself (it ships in
  `assets/fonts/`) so glyphs and the clock render correctly:
  ```sh
  mkdir -p ~/.local/share/fonts/velumeron
  cp assets/fonts/*.ttf assets/fonts/*.otf ~/.local/share/fonts/velumeron/ 2>/dev/null
  fc-cache -f
  ```

## Appearance

The lock reads its look (clock/date format, widgets, reveal animation, blur, dim,
wallpaper card) from `$VELUMERON_USER_DIR/gui/settings.json` if present, and from
`…/quickshell/colors.json` for the palette. **Both are optional** — without them the
lock falls back to built-in defaults. To customise, run the velumeron Settings →
Lockscreen editor once (it writes those files), or hand-edit the JSON.
