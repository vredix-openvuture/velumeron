# Troubleshooting

Battle-tested pitfalls, newest first.

## Colours stopped updating on wallpaper change

The wallust run is guarded by a non-blocking lock — if a wallust process hangs, every later
recolour is *silently skipped*. Diagnose:

```bash
fuser -v "$XDG_RUNTIME_DIR/vtl-wallust.lock"     # who holds the lock?
```

Known root cause: wallust broadcasts colour escape sequences to **every** `/dev/pts/*` before
templating; a pty that is never read (e.g. `gvfsd-sftp`'s ssh ptys from an SFTP mount, dead
terminals) blocks that write forever. The pipeline is hardened against this (main run skips
sequences; a 5-second best-effort pass recolours live terminals), but if you hit a stale holder:
kill it, colours resume on the next change.

## Live (video) wallpapers render black

The shell was started without the OpenGL scene graph — the mpv plugin can't render under Vulkan.
Always restart via `assets/scripts/launch-quickshell.sh` (it sets `QSG_RHI_BACKEND=opengl`).
Verify: `tr '\0' '\n' < /proc/$(pgrep -x quickshell)/environ | grep QSG`.

## `hyprctl` speaks Lua

This Hyprland runs the hypr.lua config runtime:

- `hyprctl dispatch movewindow l` → **error** ("dispatch in lua is a shorthand…"). Use
  `hyprctl dispatch 'hl.dsp.window.move({direction="left"})'`.
- `hyprctl keyword …` → "keyword can't work with non-legacy parsers. Use eval."
  Use `hyprctl eval 'hl.window_rule({ name="x", match={class="y"}, float=true })'`.
- Scripts/binds that shell out to classic `hyprctl dispatch` syntax fail **silently** when their
  output is discarded — if a bind "does nothing", check it first.
- Never run `hyprctl` from *inside* compositor Lua (bind handlers, config modules): the
  compositor is blocked in your handler → self-deadlock until timeout. Pre-share data via files
  (see `modules/fancyzones.lua` + `ZonesState.qml`).

## Shell development gotchas

- Quickshell hot-reloads on file save — but **singletons are not refreshed**: edits to
  `pragma Singleton` files silently keep the old instance. Restart via the launch script.
- Singletons in subdirectories need `import ".."` to see `VtlConfig`/`Colors`/`UiState` — a
  missing import shows up only at runtime as `ReferenceError` in `qs log` while the config still
  reports "Loaded".
- Watch the live log: `qs -p "$VELUMERON_DIR/quickshell" log`. Mid-edit reload failures are
  normal; only the last "Configuration Loaded" matters.
- Mouse binds (`{ mouse = true }`) are invoked on **press and release** — guard drag wrappers
  accordingly.

## Calendar shows "no accounts" / sync errors

- Check Settings → Calendar: the account row shows the last error inline.
- Nextcloud: use an app password; Vikunja: a CalDAV token (basic auth with the main password
  fails on OIDC setups).
- Manual test: `python3 assets/scripts/caldav-client.py sync | jq .accounts`.

## Updates module shows nothing

It collapses when everything is up to date (enable "Show when zero" in its gear). Counting needs
`checkupdates` (pacman-contrib); AUR counts need paru or yay.

## Where are the logs?

- Shell: `qs -p "$VELUMERON_DIR/quickshell" log` (`--all` lists instances)
- Launch: `/tmp/quickshell-launch.log`, mpv plugin build: `/tmp/velumeron-mpv-build.log`
- Crashes: `coredumpctl list` (quickshell has been seen SIGABRTing under heavy reload cycles)
