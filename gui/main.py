#!/usr/bin/env python3
"""Vutureland Settings — GTK4/Adwaita layer-shell panel"""

import os, sys, signal, json

# ── Toggle: kill running instance, or start if not running ───────────────────
_PID_FILE = '/tmp/vutureland-settings.pid'

if '-t' in sys.argv or '--toggle' in sys.argv:
    sys.argv = [a for a in sys.argv if a not in ('-t', '--toggle')]
    if os.path.exists(_PID_FILE):
        try:
            pid = int(open(_PID_FILE).read().strip())
            os.kill(pid, signal.SIGTERM)
            sys.exit(0)           # running → killed, nothing else to do
        except (ProcessLookupError, ValueError, OSError):
            pass                  # stale PID file → fall through and start

_LIB = '/usr/lib/libgtk4-layer-shell.so'
if 'libgtk4-layer-shell' not in os.environ.get('LD_PRELOAD', ''):
    os.environ['LD_PRELOAD'] = _LIB + ':' + os.environ.get('LD_PRELOAD', '')
    os.execv(sys.executable, [sys.executable] + sys.argv)

os.environ['GDK_BACKEND'] = 'wayland'

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
gi.require_version('Gtk4LayerShell', '1.0')

from gi.repository import Gtk, Adw, Gdk, Gio, GdkPixbuf, GLib, Gtk4LayerShell

sys.path.insert(0, os.path.dirname(__file__))

from pages.wallpaper  import WallpaperPage
from pages.hyprland   import HyprlandPage
from pages.waybar     import WaybarPage
from pages.lockscreen import LockscreenPage
from pages.settings   import SettingsPage

_CSS           = os.path.join(os.path.dirname(__file__), 'style.css')
_BANNER        = os.path.expanduser('~/.config/vutureland/assets/icons/vuturland.png')
_SETTINGS_FILE = os.path.expanduser('~/.config/vutureland/gui/settings.json')
_PANEL_WIDTH   = 900
_OPACITY_DIM   = 0.88          # opacity when transparency is enabled

_PAGES = [
    ('hyprland',   HyprlandPage,   'preferences-desktop-display-symbolic', 'Hyprland'),
    ('waybar',     WaybarPage,     'view-grid-symbolic',                   'Waybar'),
    ('wallpaper',  WallpaperPage,  'image-x-generic-symbolic',             'Wallpaper'),
    ('lockscreen', LockscreenPage, 'system-lock-screen-symbolic',          'Lockscreen'),
]
_BOTTOM_PAGES = [
    ('settings',   SettingsPage,   'preferences-system-symbolic',          'Settings'),
]


def _load_settings() -> dict:
    try:
        with open(_SETTINGS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _save_settings(data: dict) -> None:
    try:
        os.makedirs(os.path.dirname(_SETTINGS_FILE), exist_ok=True)
        with open(_SETTINGS_FILE, 'w') as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass


def _load_logo(height: int) -> GdkPixbuf.Pixbuf | None:
    if not os.path.exists(_BANNER):
        return None
    try:
        pb = GdkPixbuf.Pixbuf.new_from_file(_BANNER)
        if pb.get_has_alpha():
            w, h = pb.get_width(), pb.get_height()
            rs = pb.get_rowstride()
            p = pb.get_pixels()
            def row_empty(y):
                for x in range(w):
                    if p[y * rs + x * 4 + 3] > 10: return False
                return True
            def col_empty(x):
                for y in range(h):
                    if p[y * rs + x * 4 + 3] > 10: return False
                return True
            top = 0
            while top < h - 1 and row_empty(top): top += 1
            bottom = h - 1
            while bottom > top and row_empty(bottom): bottom -= 1
            left = 0
            while left < w - 1 and col_empty(left): left += 1
            right = w - 1
            while right > left and col_empty(right): right -= 1
            cw, ch = right - left + 1, bottom - top + 1
            cropped = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, cw, ch)
            pb.copy_area(left, top, cw, ch, cropped, 0, 0)
            pb = cropped
        scale = height / pb.get_height()
        return pb.scale_simple(max(1, int(pb.get_width() * scale)), height,
                               GdkPixbuf.InterpType.BILINEAR)
    except Exception as e:
        print(f"[logo] {e}")
        return None


class MainWindow(Gtk.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title('Vutureland Settings')
        self.set_decorated(False)
        self._settings = _load_settings()

        # ── Content stack ─────────────────────────────────────────────
        stack = Adw.ViewStack()
        for name, cls, _, _ in _PAGES + _BOTTOM_PAGES:
            page = cls()
            if hasattr(page, 'set_apply_callback'):
                page.set_apply_callback(self.close_animated)
            if isinstance(page, SettingsPage):
                page.set_opacity_callback(
                    self._apply_opacity,
                    initial=self._settings.get('opacity_enabled', False),
                )
            stack.add_named(page, name)
        stack.set_hexpand(True)
        stack.set_vexpand(True)

        # ── Content wrapper ───────────────────────────────────────────
        content_wrap = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content_wrap.add_css_class('content-area')
        content_wrap.set_hexpand(True)
        content_wrap.set_vexpand(True)
        content_wrap.append(stack)

        # ── Left sidebar ──────────────────────────────────────────────
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        sidebar.add_css_class('nav-sidebar')

        nav_btns: list[Gtk.ToggleButton] = []

        for name, _, icon, tooltip in _PAGES:
            btn = Gtk.ToggleButton()
            btn.set_icon_name(icon)
            btn.set_tooltip_text(tooltip)
            btn.add_css_class('nav-btn')
            btn.connect('toggled', self._on_nav_toggled, name, stack, nav_btns)
            sidebar.append(btn)
            nav_btns.append(btn)

        # Spacer + separator push the settings button to the bottom
        spacer = Gtk.Box()
        spacer.set_vexpand(True)
        sidebar.append(spacer)
        sep = Gtk.Separator()
        sep.set_margin_top(4)
        sep.set_margin_bottom(4)
        sidebar.append(sep)

        for name, _, icon, tooltip in _BOTTOM_PAGES:
            btn = Gtk.ToggleButton()
            btn.set_icon_name(icon)
            btn.set_tooltip_text(tooltip)
            btn.add_css_class('nav-btn')
            btn.connect('toggled', self._on_nav_toggled, name, stack, nav_btns)
            sidebar.append(btn)
            nav_btns.append(btn)

        nav_btns[0].set_active(True)
        sidebar.set_size_request(56, -1)

        # ── Body ──────────────────────────────────────────────────────
        body = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        body.add_css_class('body-area')
        body.set_hexpand(True)
        body.set_vexpand(True)
        body.append(sidebar)
        body.append(content_wrap)

        # ── Root ──────────────────────────────────────────────────────
        self._root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self._root.add_css_class('root-area')
        self._root.set_size_request(_PANEL_WIDTH, -1)
        self._root.append(self._build_banner())
        self._root.append(body)
        self.set_child(self._root)

        # Apply saved opacity (must come after self._root is assigned)
        if self._settings.get('opacity_enabled', False):
            self._root.set_opacity(_OPACITY_DIM)

        # ── Escape key closes the panel ───────────────────────────────
        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect('key-pressed', self._on_key_pressed)
        self.add_controller(key_ctrl)

    def slide_in(self):
        return False

    def close_animated(self):
        self.close()

    def _apply_opacity(self, enabled: bool):
        self._root.set_opacity(_OPACITY_DIM if enabled else 1.0)
        self._settings['opacity_enabled'] = enabled
        _save_settings(self._settings)

    def _on_key_pressed(self, ctrl, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.close_animated()
            return True
        return False

    def _build_banner(self):
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        box.add_css_class('logo-bar')
        box.set_hexpand(True)
        box.set_vexpand(False)

        pb = _load_logo(height=80)
        if pb:
            texture = Gdk.Texture.new_for_pixbuf(pb)
            pic = Gtk.Picture.new_for_paintable(texture)
            pic.set_content_fit(Gtk.ContentFit.SCALE_DOWN)
            pic.set_halign(Gtk.Align.CENTER)
            pic.set_valign(Gtk.Align.CENTER)
            pic.set_hexpand(True)
            pic.set_vexpand(False)
            pic.set_size_request(pb.get_width(), pb.get_height())
            box.append(pic)

        return box

    def _on_nav_toggled(self, btn, name, stack, btns):
        if btn.get_active():
            stack.set_visible_child_name(name)
            for b in btns:
                if b is not btn and b.get_active():
                    b.set_active(False)
        else:
            if stack.get_visible_child_name() == name:
                btn.set_active(True)


class VuturelandSettings(Adw.Application):
    def __init__(self):
        super().__init__(application_id='com.vutureland.settings',
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.connect('activate', self._activate)
        self.connect('shutdown', self._on_shutdown)
        try:
            with open(_PID_FILE, 'w') as f:
                f.write(str(os.getpid()))
        except OSError:
            pass

    def _on_shutdown(self, _):
        try:
            os.remove(_PID_FILE)
        except OSError:
            pass

    def _activate(self, _):
        p = Gtk.CssProvider()
        p.load_from_path(_CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), p,
            Gtk.STYLE_PROVIDER_PRIORITY_USER)

        win = MainWindow(application=self)

        # ── Layer shell setup (must happen before present()) ──────────
        Gtk4LayerShell.init_for_window(win)
        Gtk4LayerShell.set_namespace(win, 'vutureland-settings')
        Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.TOP)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.LEFT,   True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.BOTTOM, True)
        Gtk4LayerShell.set_exclusive_zone(win, -1)
        Gtk4LayerShell.set_keyboard_mode(win, Gtk4LayerShell.KeyboardMode.ON_DEMAND)

        # SIGTERM handler — used by --toggle to cleanly close the panel
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM,
                             lambda: (self.quit(), GLib.SOURCE_REMOVE)[1])

        win.present()
        GLib.idle_add(win.slide_in)


if __name__ == '__main__':
    VuturelandSettings().run()
