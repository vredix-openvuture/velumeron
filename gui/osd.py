#!/usr/bin/env python3
"""Vutureland OSD — brightness/volume/workspace banner (GTK4 layer-shell daemon).

Listens on a FIFO for one-line commands:
    echo "volume"        > $XDG_RUNTIME_DIR/vutureland-osd.fifo
    echo "brightness 80" > $XDG_RUNTIME_DIR/vutureland-osd.fifo

Also connects to the Hyprland socket2 event stream for workspace events.
Position, display modes, and colours all come from osd_config.json.
"""
from __future__ import annotations
import os, re, subprocess, json
import socket as _socket
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Gtk4LayerShell', '1.0')
from gi.repository import Gtk, GLib, Gio, Gdk, Pango, Gtk4LayerShell as LayerShell

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
    user = os.path.join(_user_dir(), 'assets', 'colors_gtk.css')
    return user if os.path.exists(user) else os.path.join(_pkg_dir(), 'assets', 'colors_gtk.css')


def _hyprland_socket2() -> str | None:
    his = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')
    if his:
        return os.path.join(_RUNTIME, 'hypr', his, '.socket2.sock')
    hypr_dir = os.path.join(_RUNTIME, 'hypr')
    if os.path.isdir(hypr_dir):
        for name in os.listdir(hypr_dir):
            p = os.path.join(hypr_dir, name, '.socket2.sock')
            if os.path.exists(p):
                return p
    return None


_OSD_CSS = b"""
window.osd-window { background-color: transparent; box-shadow: none; }
.osd-root {
    background-color: @bg-element;
    border: 2px solid @bo-normal;
    border-radius: 18px;
    padding: 0 22px;
}
.osd-root image  { color: @fg-primary; }
.osd-root label  { color: @fg-muted; font-weight: bold; }
.osd-root .osd-name { color: @fg-muted; font-size: 0.85em; }
.osd-root .osd-ws-num {
    color: @fg-primary;
    font-size: 1.3em;
    font-weight: bold;
}
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
/* Vertical bar (center-left / center-right positions) */
.osd-root progressbar.vertical {
    min-width: 9px;
}
.osd-root progressbar.vertical > trough {
    min-height: unset;
    min-width: 9px;
}
.osd-root progressbar.vertical > trough > progress {
    min-height: unset;
    min-width: 9px;
}
/* Vertical OSD (center-left / center-right): swap horizontal padding to vertical */
.osd-root.osd-vertical { padding: 22px 0; }
/* Dock mode: flatten the corner(s) and drop the border on the screen-edge side */
.osd-root.osd-dock-bottom {
    border-bottom-left-radius: 0;
    border-bottom-right-radius: 0;
    border-bottom-color: transparent;
    padding-top: 10px;
}
.osd-root.osd-dock-top {
    border-top-left-radius: 0;
    border-top-right-radius: 0;
    border-top-color: transparent;
    padding-bottom: 10px;
}
.osd-root.osd-dock-left {
    border-top-left-radius: 0;
    border-bottom-left-radius: 0;
    border-left-color: transparent;
    padding-right: 10px;
}
.osd-root.osd-dock-right {
    border-top-right-radius: 0;
    border-bottom-right-radius: 0;
    border-right-color: transparent;
    padding-left: 10px;
}
.ws-dot {
    border-radius: 9px;
    background-color: alpha(@fg-primary, 0.2);
    min-width: 7px;
    min-height: 7px;
}
.ws-dot.active {
    background-color: @bo-active;
    min-width: 11px;
    min-height: 11px;
}
"""


def _volume_icon(pct: int, muted: bool) -> str:
    if muted or pct <= 0:  return 'audio-volume-muted-symbolic'
    if pct < 34:           return 'audio-volume-low-symbolic'
    if pct < 67:           return 'audio-volume-medium-symbolic'
    return 'audio-volume-high-symbolic'


# ─── Position helpers ─────────────────────────────────────────────────────────

def _parse_position(pos: str) -> tuple[str, str, bool, str]:
    """Return (v_edge, h_align, is_vertical, anim_dir).

    v_edge:      'bottom' | 'top' | 'center'
    h_align:     'left' | 'center' | 'right'
    is_vertical: True for center-left / center-right
    anim_dir:    direction for the layerrule animation namespace
    """
    parts = pos.split('-')
    if not parts:
        return 'bottom', 'center', False, 'bottom'
    if parts[0] == 'center':
        side = parts[1] if len(parts) > 1 else 'left'
        return 'center', side, True, side
    v = parts[0] if parts[0] in ('bottom', 'top') else 'bottom'
    h = parts[1] if len(parts) > 1 and parts[1] in ('left', 'center', 'right') else 'center'
    return v, h, False, v


class Osd:
    def __init__(self, app: Gtk.Application):
        self._app = app
        self._hide_id: int | None = None
        self._sink_cache: tuple[str, int] = ('', 0)
        self._current_monitor: object = None   # currently locked GDK monitor (for workspace OSD)
        self._current_position: str = ''       # cached to avoid redundant _apply_position calls
        self._is_vertical: bool = False
        self._margin_edge = LayerShell.Edge.BOTTOM

        self._colors_provider = Gtk.CssProvider()
        self._osd_provider    = Gtk.CssProvider()
        display = Gdk.Display.get_default()
        for prov in (self._colors_provider, self._osd_provider):
            Gtk.StyleContext.add_provider_for_display(
                display, prov, Gtk.STYLE_PROVIDER_PRIORITY_USER)

        # ── Window ───────────────────────────────────────────────────────────
        self.win = Gtk.Window(application=app)
        self.win.set_decorated(False)
        self.win.add_css_class('osd-window')
        LayerShell.init_for_window(self.win)
        LayerShell.set_namespace(self.win, 'vutureland-osd-bottom')  # overridden by _apply_position
        LayerShell.set_layer(self.win, LayerShell.Layer.OVERLAY)
        LayerShell.set_keyboard_mode(self.win, LayerShell.KeyboardMode.NONE)

        # ── Widgets ──────────────────────────────────────────────────────────
        self._build_widgets()

        # ── Apply initial config ─────────────────────────────────────────────
        cfg = osd_config.load()
        self._apply_position(cfg.get('osd_position', 'bottom-center'))
        self._reload_css()

    # ── Widget tree ───────────────────────────────────────────────────────────

    def _build_widgets(self):
        """Build the widget tree (called once at init)."""
        # Horizontal root (orientation changed in _apply_position for vertical mode)
        self._root = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        self._root.add_css_class('osd-root')

        self._icon = Gtk.Image()
        self._icon.set_pixel_size(30)
        self._icon.set_halign(Gtk.Align.CENTER)
        self._icon.set_valign(Gtk.Align.CENTER)
        self._root.append(self._icon)

        # Centre column — holds bar, device name, dots, workspace number
        self._centre = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._centre.set_hexpand(True)
        self._centre.set_vexpand(False)
        self._centre.set_halign(Gtk.Align.FILL)
        self._centre.set_valign(Gtk.Align.CENTER)

        self._bar = Gtk.ProgressBar()
        self._bar.set_hexpand(True)
        self._centre.append(self._bar)

        self._name = Gtk.Label(label='')
        self._name.add_css_class('osd-name')
        self._name.set_ellipsize(Pango.EllipsizeMode.END)
        self._name.set_max_width_chars(32)
        self._name.set_xalign(0.5)
        self._name.set_visible(False)
        self._centre.append(self._name)

        self._dots_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self._dots_box.set_halign(Gtk.Align.CENTER)
        self._dots_box.set_valign(Gtk.Align.CENTER)
        self._dots_box.set_visible(False)
        self._centre.append(self._dots_box)

        self._root.append(self._centre)

        # Value label (e.g. "75%") — right of bar for horizontal, below for vertical
        self._label = Gtk.Label(label='')
        self._label.set_width_chars(5)
        self._label.set_xalign(1.0)
        self._label.set_valign(Gtk.Align.CENTER)
        self._root.append(self._label)

        self.win.set_child(self._root)

    # ── Position ──────────────────────────────────────────────────────────────

    def _edge_margin(self, cfg: dict) -> int:
        """Primary-edge margin: 0 in dock mode (flush against screen), margin_px in float mode."""
        return 0 if cfg.get('osd_style', 'float') == 'dock' else cfg['margin_px']

    def _apply_position(self, position: str):
        """Set layer-shell anchors, margin, namespace and widget layout orientation."""
        cfg = osd_config.load()
        style = cfg.get('osd_style', 'float')
        cache_key = f'{position}:{style}'
        if cache_key == self._current_position:
            return
        was_visible = self.win.get_visible()
        if was_visible:
            self.win.set_visible(False)

        v_edge, h_align, is_vertical, anim_dir = _parse_position(position)
        margin = self._edge_margin(cfg)

        # Clear all anchors and margins first
        for edge in (LayerShell.Edge.BOTTOM, LayerShell.Edge.TOP,
                     LayerShell.Edge.LEFT,   LayerShell.Edge.RIGHT):
            LayerShell.set_anchor(self.win, edge, False)
            LayerShell.set_margin(self.win, edge, 0)

        if is_vertical:
            # center-left / center-right: anchor to one horizontal edge only → vertically centered
            if h_align == 'left':
                LayerShell.set_anchor(self.win, LayerShell.Edge.LEFT, True)
                self._margin_edge = LayerShell.Edge.LEFT
            else:
                LayerShell.set_anchor(self.win, LayerShell.Edge.RIGHT, True)
                self._margin_edge = LayerShell.Edge.RIGHT
        else:
            # bottom/top row
            if v_edge == 'bottom':
                LayerShell.set_anchor(self.win, LayerShell.Edge.BOTTOM, True)
                self._margin_edge = LayerShell.Edge.BOTTOM
            else:
                LayerShell.set_anchor(self.win, LayerShell.Edge.TOP, True)
                self._margin_edge = LayerShell.Edge.TOP
            # horizontal alignment
            if h_align == 'left':
                LayerShell.set_anchor(self.win, LayerShell.Edge.LEFT, True)
            elif h_align == 'right':
                LayerShell.set_anchor(self.win, LayerShell.Edge.RIGHT, True)
            # 'center' → no left/right anchor → compositor centers it

        LayerShell.set_margin(self.win, self._margin_edge, margin)
        # For corner positions: in float mode push away from the side edge too;
        # in dock mode the OSD sits flush against both anchored edges.
        if not is_vertical and h_align in ('left', 'right'):
            side_edge = LayerShell.Edge.LEFT if h_align == 'left' else LayerShell.Edge.RIGHT
            LayerShell.set_margin(self.win, side_edge, margin)
        LayerShell.set_namespace(self.win, f'vutureland-osd-{anim_dir}')

        # ── Layout orientation ────────────────────────────────────────────────
        self._is_vertical = is_vertical

        if is_vertical:
            # Add padding class; reorder to: label (top) → centre (bar) → icon (bottom)
            self._root.add_css_class('osd-vertical')
            self._root.reorder_child_after(self._label, None)           # label → first
            self._root.reorder_child_after(self._centre, self._label)   # centre → second
        else:
            self._root.remove_css_class('osd-vertical')
            # Restore original order: icon → centre → label
            self._root.reorder_child_after(self._icon, None)            # icon → first
            self._root.reorder_child_after(self._centre, self._icon)    # centre → second

        if is_vertical:
            self._root.set_orientation(Gtk.Orientation.VERTICAL)
            self._root.set_spacing(12)
            self._bar.set_orientation(Gtk.Orientation.VERTICAL)
            self._bar.set_inverted(True)   # fill from bottom upward
            self._bar.set_vexpand(True)
            self._bar.set_hexpand(True)
            self._bar.set_halign(Gtk.Align.FILL)
            self._bar.set_size_request(-1, -1)
            self._centre.set_hexpand(False)
            self._centre.set_vexpand(True)
            self._centre.set_halign(Gtk.Align.FILL)
            self._centre.set_valign(Gtk.Align.FILL)  # must be FILL for vexpand to work
            self._dots_box.set_orientation(Gtk.Orientation.VERTICAL)
            self._icon.set_halign(Gtk.Align.CENTER)
            self._label.set_xalign(0.5)
            self._label.set_width_chars(-1)
            # Vertical banner: narrow × tall (swap width_px / height_px)
            self._root.set_size_request(cfg['height_px'], cfg['width_px'])
            self.win.set_default_size(cfg['height_px'], cfg['width_px'])
        else:
            self._root.set_orientation(Gtk.Orientation.HORIZONTAL)
            self._root.set_spacing(16)
            self._bar.set_orientation(Gtk.Orientation.HORIZONTAL)
            self._bar.set_inverted(False)
            self._bar.set_hexpand(True)
            self._bar.set_vexpand(False)
            self._bar.set_halign(Gtk.Align.FILL)
            self._bar.set_size_request(-1, -1)  # reset to natural size
            self._centre.set_hexpand(True)
            self._centre.set_vexpand(False)
            self._centre.set_halign(Gtk.Align.FILL)
            self._centre.set_valign(Gtk.Align.CENTER)  # restore: center vertically in horizontal strip
            self._dots_box.set_orientation(Gtk.Orientation.HORIZONTAL)
            self._icon.set_halign(Gtk.Align.CENTER)
            self._label.set_xalign(1.0)
            self._label.set_width_chars(5)
            self._root.set_size_request(cfg['width_px'], cfg['height_px'])

        # ── Dock edge styling ─────────────────────────────────────────────────
        _DOCK_CLASSES = ('osd-dock-bottom', 'osd-dock-top',
                         'osd-dock-left',   'osd-dock-right')
        for cls in _DOCK_CLASSES:
            self._root.remove_css_class(cls)
        if style == 'dock':
            if is_vertical:
                self._root.add_css_class(f'osd-dock-{h_align}')
            else:
                self._root.add_css_class(f'osd-dock-{v_edge}')
                if h_align in ('left', 'right'):
                    self._root.add_css_class(f'osd-dock-{h_align}')

        self._current_position = cache_key

    # ── Public show entrypoints ───────────────────────────────────────────────

    def show_volume(self):
        cfg = osd_config.load()
        self._apply_position(cfg.get('osd_position', 'bottom-center'))
        pct, muted = self._read_volume()
        device = self._sink_name() if cfg.get('show_device') else ''
        display = cfg.get('volume_display', 'bar_and_value')
        self._present(_volume_icon(pct, muted), pct, muted, device, display)

    def show_brightness(self, pct: int):
        cfg = osd_config.load()
        self._apply_position(cfg.get('osd_position', 'bottom-center'))
        pct = max(0, min(100, pct))
        display = cfg.get('brightness_display', 'bar_and_value')
        self._present('display-brightness-symbolic', pct, False, '', display)

    def show_text(self, icon: str, text: str):
        """Show a simple icon + text banner (no bar, no value label)."""
        cfg = osd_config.load()
        self._apply_position(cfg.get('osd_position', 'bottom-center'))
        self._bar.set_visible(False)
        self._dots_box.set_visible(False)
        self._label.set_visible(False)
        self._label.remove_css_class('osd-ws-num')
        self._icon.set_from_icon_name(icon)
        self._name.set_text(text)
        self._name.set_visible(True)
        LayerShell.set_margin(self.win, self._margin_edge, self._edge_margin(cfg))
        if self._is_vertical:
            self._root.set_size_request(cfg['height_px'], cfg['width_px'])
        else:
            self._root.set_size_request(cfg['width_px'], cfg['height_px'])
        self._reload_css()
        self.win.set_visible(True)
        if self._hide_id is not None:
            GLib.source_remove(self._hide_id)
        self._hide_id = GLib.timeout_add(cfg['duration_ms'], self._hide)

    def show_workspace(self, ws_num: int, monitor_name: str = ''):
        cfg = osd_config.load()
        self._apply_position(cfg.get('osd_position', 'bottom-center'))
        self._set_monitor(monitor_name or None)
        ws_ids = self._get_monitor_workspaces(monitor_name, ws_num)
        display = cfg.get('workspace_display', 'dots_only')

        # Reset to workspace mode — dots in centre, number reuses _label (right slot)
        self._bar.set_visible(False)
        self._name.set_visible(False)
        show_dots   = display in ('dots_only', 'dots_and_number')
        show_number = display in ('number_only', 'dots_and_number')
        self._dots_box.set_visible(show_dots)
        self._label.set_visible(show_number)

        if show_dots:
            self._update_dots(ws_ids, ws_num)
        if show_number:
            self._label.set_text(str(ws_num))
            self._label.set_width_chars(-1)   # natural width — no extra padding
            self._label.add_css_class('osd-ws-num')

        self._icon.set_from_icon_name('view-grid-symbolic')

        self._duration_ms = cfg['duration_ms']
        LayerShell.set_margin(self.win, self._margin_edge, self._edge_margin(cfg))
        if self._is_vertical:
            self._root.set_size_request(cfg['height_px'], cfg['width_px'])
        else:
            self._root.set_size_request(cfg['width_px'], cfg['height_px'])
        self._reload_css()
        self.win.set_visible(True)
        if self._hide_id is not None:
            GLib.source_remove(self._hide_id)
        self._hide_id = GLib.timeout_add(cfg['duration_ms'], self._hide)

    # ── Internals ─────────────────────────────────────────────────────────────

    def _present(self, icon: str, pct: int, muted: bool,
                 device: str = '', display_mode: str = 'bar_and_value'):
        """Show a volume/brightness banner with the requested display_mode."""
        # Reset workspace mode styling
        self._dots_box.set_visible(False)
        self._label.remove_css_class('osd-ws-num')
        if not self._is_vertical:
            self._label.set_width_chars(5)   # reserve width for "muted" / "100%"

        show_bar   = display_mode in ('bar_and_value', 'bar_only')
        show_label = display_mode in ('bar_and_value', 'value_only')

        self._bar.set_visible(show_bar)
        self._label.set_visible(show_label)

        cfg = osd_config.load()
        self._duration_ms = cfg['duration_ms']
        LayerShell.set_margin(self.win, self._margin_edge, self._edge_margin(cfg))
        if self._is_vertical:
            self._root.set_size_request(cfg['height_px'], cfg['width_px'])
        else:
            self._root.set_size_request(cfg['width_px'], cfg['height_px'])

        self._reload_css()
        self._icon.set_from_icon_name(icon)
        self._name.set_text(device)
        self._name.set_visible(bool(device))
        if show_bar:
            self._bar.set_fraction(min(pct / 100.0, 1.0))
        if show_label:
            self._label.set_text('muted' if muted else f'{pct}%')

        self.win.set_visible(True)
        if self._hide_id is not None:
            GLib.source_remove(self._hide_id)
        self._hide_id = GLib.timeout_add(cfg['duration_ms'], self._hide)

    def _hide(self) -> bool:
        self._hide_id = None
        self.win.set_visible(False)
        return False

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

    def _gdk_monitor_for(self, connector: str):
        display = Gdk.Display.get_default()
        mons = display.get_monitors()
        for i in range(mons.get_n_items()):
            m = mons.get_item(i)
            if m.get_connector() == connector:
                return m
        return None

    def _set_monitor(self, monitor_name: str | None):
        """Lock the layer-shell surface to a specific GDK monitor.
        Passing None or empty string keeps whatever monitor is currently assigned
        (avoids calling set_monitor(None) which can be unreliable in some bindings).
        """
        if not monitor_name:
            # Only reset if currently locked
            if self._current_monitor is not None:
                self.win.set_visible(False)
                self._current_monitor = None
            return
        gdk_mon = self._gdk_monitor_for(monitor_name)
        if gdk_mon is None or gdk_mon is self._current_monitor:
            return
        self.win.set_visible(False)
        try:
            LayerShell.set_monitor(self.win, gdk_mon)
            self._current_monitor = gdk_mon
        except Exception as e:
            print(f'[osd] set_monitor error: {e}')

    def _get_monitor_workspaces(self, monitor_name: str, active_ws: int) -> list[int]:
        try:
            out = subprocess.run(
                ['hyprctl', 'workspaces', '-j'],
                capture_output=True, text=True, timeout=1).stdout
            data = json.loads(out)
            ids = sorted(set(
                [ws['id'] for ws in data
                 if ws.get('monitor') == monitor_name and ws['id'] > 0]
                + [active_ws]
            ))
            return ids
        except Exception:
            return [active_ws]

    def _update_dots(self, ws_ids: list[int], active: int):
        while (child := self._dots_box.get_first_child()) is not None:
            self._dots_box.remove(child)
        for ws_id in ws_ids:
            dot = Gtk.Box()
            dot.add_css_class('ws-dot')
            if ws_id == active:
                dot.add_css_class('active')
            self._dots_box.append(dot)

    def _reload_css(self):
        try:
            self._colors_provider.load_from_path(_colors_css())
        except Exception:
            pass
        self._osd_provider.load_from_string(_OSD_CSS.decode())

    # ── FIFO listener ─────────────────────────────────────────────────────────

    def setup_fifo(self):
        try:
            if not os.path.exists(FIFO):
                os.mkfifo(FIFO, 0o600)
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
        # Coalesce bursts (held key) — only handle the newest message
        latest = next((ln.strip() for ln in reversed(lines) if ln.strip()), '')
        if latest:
            self._dispatch(latest)
        return True

    def _dispatch(self, line: str):
        if not line:
            return
        cfg = osd_config.load()
        parts = line.split()
        cmd = parts[0]
        if cmd == 'volume' and cfg.get('osd_volume', True):
            self.show_volume()
        elif cmd == 'brightness' and cfg.get('osd_brightness', True):
            try:
                pct = int(parts[1]) if len(parts) > 1 else 0
            except ValueError:
                pct = 0
            self.show_brightness(pct)
        elif cmd == 'notify':
            icon = parts[1] if len(parts) > 1 else 'dialog-information-symbolic'
            text = ' '.join(parts[2:]) if len(parts) > 2 else ''
            self.show_text(icon, text)

    # ── Hyprland event socket (workspace OSD) ─────────────────────────────────

    def setup_hyprland_events(self):
        sock_path = _hyprland_socket2()
        if not sock_path:
            print('[osd] hyprland socket not found — workspace OSD unavailable')
            return
        try:
            sock = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
            sock.connect(sock_path)
            sock.setblocking(False)
            self._hypr_sock = sock
            self._hypr_buf  = ''
            GLib.unix_fd_add_full(GLib.PRIORITY_DEFAULT, sock.fileno(),
                                  GLib.IOCondition.IN, self._on_hypr_event, None)
            print(f'[osd] hyprland event socket connected: {sock_path}')
        except OSError as e:
            print(f'[osd] hyprland socket connect failed: {e}')

    def _on_hypr_event(self, fd: int, _cond, _data) -> bool:
        try:
            chunk = self._hypr_sock.recv(65536)
        except OSError:
            return True
        if not chunk:
            return True
        self._hypr_buf += chunk.decode(errors='ignore')
        while '\n' in self._hypr_buf:
            line, self._hypr_buf = self._hypr_buf.split('\n', 1)
            line = line.strip()
            if line:
                self._handle_hypr_event(line)
        return True

    def _handle_hypr_event(self, line: str):
        if not osd_config.load().get('osd_workspace', True):
            return

        ws_num: int | None = None
        monitor_name = ''

        if line.startswith('workspace>>'):
            try:
                ws_num = int(line[len('workspace>>'):])
            except ValueError:
                return
            monitor_name = self._get_focused_monitor()

        elif line.startswith('focusedmon>>'):
            if osd_config.load().get('osd_workspace_local_only', True):
                return
            rest = line[len('focusedmon>>'):]
            idx = rest.find(',')
            if idx < 0:
                return
            monitor_name = rest[:idx]
            try:
                ws_num = int(rest[idx + 1:])
            except ValueError:
                return

        if ws_num is not None:
            self.show_workspace(ws_num, monitor_name)

    def _get_focused_monitor(self) -> str:
        try:
            out = subprocess.run(
                ['hyprctl', 'activeworkspace', '-j'],
                capture_output=True, text=True, timeout=1).stdout
            return json.loads(out).get('monitor', '')
        except Exception:
            return ''


class OsdApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='land.vuture.osd',
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_activate(self):
        self.hold()
        try:
            Gtk.Settings.get_default().set_property('gtk-icon-theme-name', 'Adwaita')
        except Exception:
            pass
        if not hasattr(self, '_osd'):
            self._osd = Osd(self)
            self._osd.setup_fifo()
            self._osd.setup_hyprland_events()


if __name__ == '__main__':
    OsdApp().run(None)
