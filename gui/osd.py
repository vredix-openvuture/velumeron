#!/usr/bin/env python3
"""Vutureland OSD — bottom-centre brightness/volume banner in the GUI style.

A tiny GTK4 layer-shell daemon. It listens on a FIFO for one-line messages and
shows a banner with an icon + progress bar, then fades out after a moment:

    echo "volume"        > $XDG_RUNTIME_DIR/vutureland-osd.fifo   # reads live sink volume
    echo "brightness 80" > $XDG_RUNTIME_DIR/vutureland-osd.fifo   # shows the given percent

Colours come from wallust's colors_gtk.css (same @bg-element/@bo-active/@fg-*
tokens the GUI uses), reloaded on every show so it always matches the theme.
The keybinds (keybinds.lua) write to the FIFO via assets/scripts/osd-show.sh.
"""
from __future__ import annotations
import os, re, subprocess
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Gtk4LayerShell', '1.0')
from gi.repository import Gtk, GLib, Gio, Pango, Gtk4LayerShell as LayerShell

import osd_config

_RUNTIME = os.environ.get('XDG_RUNTIME_DIR') or '/tmp'
FIFO     = os.path.join(_RUNTIME, 'vutureland-osd.fifo')


def _user_dir() -> str:
    xdg = os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config'))
    return os.environ.get('VUTURELAND_USER_DIR', os.path.join(xdg, 'vutureland'))


def _pkg_dir() -> str:
    return os.environ.get('VUTURELAND_DIR',
                          os.path.realpath(os.path.join(os.path.dirname(__file__), '..')))


def _colors_css() -> str:
    """Live wallust palette from the user dir, falling back to the package copy."""
    user = os.path.join(_user_dir(), 'assets', 'colors_gtk.css')
    return user if os.path.exists(user) else os.path.join(_pkg_dir(), 'assets', 'colors_gtk.css')


# Banner styling — leans on the same colour tokens as the GUI's style.css.
# `window.osd-window` (element + class) outranks Adwaita's `.background`, so the
# layer is truly transparent — only the rounded banner shows. No box-shadow: the
# fade/slide is done by Hyprland's layerrule, not GTK.
_OSD_CSS = b"""
window.osd-window { background-color: transparent; box-shadow: none; }
.osd-root {
    background-color: @bg-element;
    border: 2px solid @bo-normal;
    border-radius: 18px;
    padding: 0 22px;
}
.osd-root image { color: @fg-primary; }
.osd-root label { color: @fg-muted; font-weight: bold; }
.osd-root .osd-name { color: @fg-muted; font-size: 0.85em; }
.osd-root progressbar > trough {
    min-height: 9px;
    border-radius: 9px;
    background-color: @bg-secondary;
    border: none;
}
.osd-root progressbar > trough > progress {
    min-height: 9px;
    border-radius: 9px;
    background-color: @bo-active;
}
"""


def _volume_icon(pct: int, muted: bool) -> str:
    if muted or pct <= 0:
        return 'audio-volume-muted-symbolic'
    if pct < 34:
        return 'audio-volume-low-symbolic'
    if pct < 67:
        return 'audio-volume-medium-symbolic'
    return 'audio-volume-high-symbolic'


class Osd:
    def __init__(self, app: Gtk.Application):
        self._app = app
        self._hide_id: int | None = None
        self._sink_cache: tuple[str, int] = ('', 0)

        self._colors_provider = Gtk.CssProvider()
        self._osd_provider = Gtk.CssProvider()
        display = self._app_display()
        for prov in (self._colors_provider, self._osd_provider):
            Gtk.StyleContext.add_provider_for_display(
                display, prov, Gtk.STYLE_PROVIDER_PRIORITY_USER)

        cfg = osd_config.load()
        self._duration_ms = cfg['duration_ms']

        self.win = Gtk.Window(application=app)
        self.win.set_decorated(False)
        self.win.add_css_class('osd-window')  # transparent → only the banner shows
        LayerShell.init_for_window(self.win)
        LayerShell.set_namespace(self.win, 'vutureland-osd')
        LayerShell.set_layer(self.win, LayerShell.Layer.OVERLAY)
        LayerShell.set_anchor(self.win, LayerShell.Edge.BOTTOM, True)  # bottom only → h-centred
        LayerShell.set_margin(self.win, LayerShell.Edge.BOTTOM, cfg['margin_px'])
        LayerShell.set_keyboard_mode(self.win, LayerShell.KeyboardMode.NONE)

        self._root = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        self._root.add_css_class('osd-root')
        self._root.set_size_request(cfg['width_px'], cfg['height_px'])

        self._icon = Gtk.Image()
        self._icon.set_pixel_size(30)
        self._icon.set_valign(Gtk.Align.CENTER)
        self._root.append(self._icon)

        # Centre column: progress bar, with the optional device name beneath it.
        centre = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        centre.set_hexpand(True)
        centre.set_valign(Gtk.Align.CENTER)

        self._bar = Gtk.ProgressBar()
        self._bar.set_hexpand(True)
        centre.append(self._bar)

        # Output-device name (volume only, when enabled in settings).
        self._name = Gtk.Label(label='')
        self._name.add_css_class('osd-name')
        self._name.set_ellipsize(Pango.EllipsizeMode.END)
        self._name.set_max_width_chars(32)
        self._name.set_xalign(0.5)
        centre.append(self._name)

        self._root.append(centre)

        self._label = Gtk.Label(label='')
        self._label.set_width_chars(4)
        self._label.set_xalign(1.0)
        self._label.set_valign(Gtk.Align.CENTER)
        self._root.append(self._label)

        # No GTK animation — Hyprland's layerrule (see modules/layerrules.lua,
        # namespace "vutureland-osd") handles the slide/fade on map and unmap.
        self.win.set_child(self._root)

        self._reload_css()

    def _app_display(self):
        d = self.win.get_display() if hasattr(self, 'win') else None
        from gi.repository import Gdk
        return d or Gdk.Display.get_default()

    def _reload_css(self):
        try:
            self._colors_provider.load_from_path(_colors_css())
        except Exception:
            pass
        # Reparse the OSD rules so @colour refs resolve against the fresh palette.
        self._osd_provider.load_from_string(_OSD_CSS.decode())

    # ── public show entrypoints ──────────────────────────────────────────────

    def show_volume(self):
        pct, muted = self._read_volume()
        device = self._sink_name() if osd_config.load().get('show_device') else ''
        self._present(_volume_icon(pct, muted), pct, muted, device)

    def show_brightness(self, pct: int):
        pct = max(0, min(100, pct))
        self._present('display-brightness-symbolic', pct, False, '')

    # ── internals ────────────────────────────────────────────────────────────

    def _read_volume(self) -> tuple[int, bool]:
        try:
            out = subprocess.run(
                ['wpctl', 'get-volume', '@DEFAULT_AUDIO_SINK@'],
                capture_output=True, text=True, timeout=1).stdout
        except Exception:
            return 0, False
        m = re.search(r'([0-9]+\.[0-9]+)', out)
        vol = float(m.group(1)) if m else 0.0
        return round(vol * 100), ('MUTED' in out)

    def _sink_name(self) -> str:
        """Friendly name of the current default output device (cached 1.5s so a
        held key doesn't spawn a wpctl subprocess on every repeat)."""
        now = GLib.get_monotonic_time()
        name, ts = self._sink_cache
        if name and now - ts < 1_500_000:
            return name
        try:
            out = subprocess.run(
                ['wpctl', 'inspect', '@DEFAULT_AUDIO_SINK@'],
                capture_output=True, text=True, timeout=1).stdout
        except Exception:
            return name
        result = ''
        for key in ('node.description', 'node.nick', 'node.name'):
            m = re.search(rf'{re.escape(key)}\s*=\s*"([^"]+)"', out)
            if m:
                result = m.group(1)
                break
        self._sink_cache = (result, now)
        return result

    def _present(self, icon: str, pct: int, muted: bool, device: str = ''):
        cfg = osd_config.load()
        self._duration_ms = cfg['duration_ms']
        LayerShell.set_margin(self.win, LayerShell.Edge.BOTTOM, cfg['margin_px'])
        self._root.set_size_request(cfg['width_px'], cfg['height_px'])

        self._reload_css()
        self._icon.set_from_icon_name(icon)
        self._name.set_text(device)
        self._name.set_visible(bool(device))
        self._bar.set_fraction(min(pct / 100.0, 1.0))
        self._label.set_text('muted' if muted else f'{pct}%')

        self.win.set_visible(True)  # Hyprland's layerrule animates the map

        if self._hide_id is not None:
            GLib.source_remove(self._hide_id)
        self._hide_id = GLib.timeout_add(self._duration_ms, self._hide)

    def _hide(self) -> bool:
        self._hide_id = None
        self.win.set_visible(False)  # Hyprland's layerrule animates the unmap
        return False

    # ── FIFO listener ────────────────────────────────────────────────────────

    def setup_fifo(self):
        try:
            if not os.path.exists(FIFO):
                os.mkfifo(FIFO, 0o600)
            # O_RDWR so the daemon always holds a writer too and never sees EOF
            # when a client closes its end.
            self._fd = os.open(FIFO, os.O_RDWR | os.O_NONBLOCK)
        except OSError as e:
            print(f'[osd] fifo setup failed: {e}')
            return
        self._buf = ''
        GLib.unix_fd_add_full(GLib.PRIORITY_DEFAULT, self._fd,
                              GLib.IOCondition.IN, self._on_fifo, None)

    def _on_fifo(self, fd, _cond, _data) -> bool:
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return True
        if not chunk:
            return True
        self._buf += chunk.decode(errors='ignore')
        if '\n' not in self._buf:
            return True
        *lines, self._buf = self._buf.split('\n')
        # Coalesce a burst (held key fires ~25×/s) down to the newest message, so
        # the daemon never falls behind — the banner tracks the live value instead
        # of draining a backlog only after the key is released.
        latest = next((ln.strip() for ln in reversed(lines) if ln.strip()), '')
        if latest:
            self._dispatch(latest)
        return True

    def _dispatch(self, line: str):
        if not line:
            return
        parts = line.split()
        cmd = parts[0]
        if cmd == 'volume':
            self.show_volume()
        elif cmd == 'brightness':
            try:
                pct = int(parts[1]) if len(parts) > 1 else 0
            except ValueError:
                pct = 0
            self.show_brightness(pct)


class OsdApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='land.vuture.osd',
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_activate(self):
        self.hold()  # stay alive with no visible window
        # Adwaita ships every freedesktop symbolic name we need; the system icon
        # theme may not, so pin it like the main GUI does.
        try:
            Gtk.Settings.get_default().set_property('gtk-icon-theme-name', 'Adwaita')
        except Exception:
            pass
        if not hasattr(self, '_osd'):
            self._osd = Osd(self)
            self._osd.setup_fifo()


if __name__ == '__main__':
    OsdApp().run(None)
