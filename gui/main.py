#!/usr/bin/env python3
"""Vutureland Settings — GTK4/Adwaita layer-shell panel"""

import os, sys

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

from pages.wallpaper import WallpaperPage
from pages.hyprland import HyprlandPage
from pages.waybar import WaybarPage
from pages.lockscreen import LockscreenPage

_CSS    = os.path.join(os.path.dirname(__file__), 'style.css')
_BANNER = os.path.expanduser('~/.config/vutureland/assets/icons/vutureland.png')
_PANEL_WIDTH = 900

_PAGES = [
    ('hyprland',   HyprlandPage,   'preferences-desktop-display-symbolic', 'Hyprland'),
    ('waybar',     WaybarPage,     'view-grid-symbolic',                   'Waybar'),
    ('wallpaper',  WallpaperPage,  'image-x-generic-symbolic',             'Wallpaper'),
    ('lockscreen', LockscreenPage, 'system-lock-screen-symbolic',          'Lockscreen'),
]


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

        # ── Content stack ─────────────────────────────────────────────
        stack = Adw.ViewStack()
        for name, cls, _, _ in _PAGES:
            stack.add_named(cls(), name)
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

        nav_btns = []
        for name, _, icon, tooltip in _PAGES:
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
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        root.add_css_class('root-area')
        root.set_size_request(_PANEL_WIDTH, -1)
        root.append(self._build_banner())
        root.append(body)

        # ── Revealer for slide-in animation ───────────────────────────
        self._revealer = Gtk.Revealer()
        self._revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_UP)
        self._revealer.set_transition_duration(280)
        self._revealer.set_reveal_child(False)
        self._revealer.set_child(root)

        self.set_child(self._revealer)

        # ── Escape key closes the panel ───────────────────────────────
        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect('key-pressed', self._on_key_pressed)
        self.add_controller(key_ctrl)

    def slide_in(self):
        self._revealer.set_reveal_child(True)
        return False

    def close_animated(self):
        self._revealer.set_reveal_child(False)
        GLib.timeout_add(290, self.close)

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

    def _activate(self, _):
        p = Gtk.CssProvider()
        p.load_from_path(_CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), p,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        win = MainWindow(application=self)

        # ── Layer shell setup (must happen before present()) ──────────
        print(f"[layer-shell] supported: {Gtk4LayerShell.is_supported()}")
        Gtk4LayerShell.init_for_window(win)
        print(f"[layer-shell] is_layer_window: {Gtk4LayerShell.is_layer_window(win)}")
        Gtk4LayerShell.set_namespace(win, 'vutureland-settings')
        Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.TOP)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.LEFT,   True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.BOTTOM, True)
        Gtk4LayerShell.set_exclusive_zone(win, -1)
        Gtk4LayerShell.set_keyboard_mode(win, Gtk4LayerShell.KeyboardMode.EXCLUSIVE)

        win.present()
        GLib.idle_add(win.slide_in)


if __name__ == '__main__':
    VuturelandSettings().run()
