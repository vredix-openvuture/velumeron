#!/usr/bin/env python3
"""Vutureland Keybind Help — floating cheatsheet (SUPER+SHIFT+/)"""

import os, sys, signal

_LIB = '/usr/lib/libgtk4-layer-shell.so'
if 'libgtk4-layer-shell' not in os.environ.get('LD_PRELOAD', ''):
    os.environ['LD_PRELOAD'] = _LIB + ':' + os.environ.get('LD_PRELOAD', '')
    os.execv(sys.executable, [sys.executable] + sys.argv)

os.environ['GDK_BACKEND'] = 'wayland'

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
gi.require_version('Gtk4LayerShell', '1.0')
from gi.repository import Gtk, Adw, Gdk, Gio, GLib, Gtk4LayerShell


# ── Keybind data ─────────────────────────────────────────────────────────────
# Structure: list of GROUPS.  Each group is a list of BLOCKS.
# Groups are separated by a visual divider.
# Each block: (title, [(key, desc), ...])

_GROUPS: list[list[tuple[str, list[tuple[str, str]]]]] = [
    # ── Main layer ────────────────────────────────────────────────────────
    [
        ('SUPER', [
            ('T',        'Terminal'),
            ('W',        'Browser'),
            ('E',        'File Manager'),
            ('C',        'Close window'),
            ('F',        'Float toggle'),
            ('S',        'Notifications'),
            ('B',        'Waybar toggle'),
            ('X',        'Settings'),
            ('V',        'Clipboard'),
            ('M',        'Next monitor'),
            ('H / L',    'Workspace ← / →'),
            ('J / K',    'Next / prev window'),
            ('Tab',      'Window switcher'),
            ('Space',    'Launcher'),
            ('Enter',    'Scratchpad'),
            ('.',        'Emoji'),
            ('1 – 9',    'Switch workspace'),
            ('F1 – F12', 'Quick app'),
        ]),
        ('SUPER + SHIFT', [
            ('H / L',   'Window → WS ← / →'),
            ('J / K',   'Swap window fwd / bwd'),
            ('M',       'Window → next monitor'),
            ('S',       'Screenshot'),
            ('R',       'Screen record'),
            ('1 – 9',   'Window → workspace'),
            ('/',       'Keybind help'),
        ]),
        ('SUPER + ALT', [
            ('F',           'Fullscreen'),
            ('M',           'Maximize'),
            ('P',           'Pin'),
            ('H / J / K / L', 'Resize'),
        ]),
        ('SUPER + CTRL', [
            ('L',   'Lockscreen'),
            ('Q',   'Session menu'),
            ('C',   'Force kill'),
            ('P',   'Bitwarden'),
            ('ESC', 'Quit Hyprland'),
        ]),
    ],
    # ── Window submap ─────────────────────────────────────────────────────
    [
        ('Window submap  (SUPER + ` → W)', [
            ('H / J / K / L', 'Focus direction'),
            ('C',             'Close'),
            ('F',             'Float toggle'),
            ('T',             'Transparency'),
            ('P',             'Pseudo-tile'),
            ('G',             'Group toggle'),
            ('N / SHIFT+N',   'Group next / prev'),
            ('D / M / O',     'Layout Dwindle / Master / Split'),
            ('Space',         'Center window'),
            ('Tab',           'Window switcher'),
            ('1 – 9',         'Move to workspace'),
            ('ESC / Enter',   'Exit submap'),
        ]),
        ('Window + SHIFT', [
            ('H / J / K / L', 'Move window in tiling'),
        ]),
        ('Window + ALT', [
            ('H / J / K / L', 'Resize'),
            ('F',             'Fullscreen'),
            ('M',             'Maximize'),
            ('P',             'Pin'),
        ]),
    ],
    # ── Apps submap ───────────────────────────────────────────────────────
    [
        ('Apps submap  (SUPER + ` → A)', [
            ('T',     'Terminal'),
            ('W',     'Browser'),
            ('E',     'File manager'),
            ('N',     'Notifications'),
            ('M',     'Messenger'),
            ('O',     'Notes'),
            ('P',     'Music player'),
            ('C',     'Clock'),
            ('I',     'Mail'),
            ('K',     'Calendar'),
            ('D',     'Tasks'),
            ('V',     'Editor'),
            ('Space', 'Launcher'),
        ]),
    ],
    # ── System submap ─────────────────────────────────────────────────────
    [
        ('System submap  (SUPER + ` → S)', [
            ('W',   'Wi-Fi menu'),
            ('B',   'Bluetooth menu'),
            ('V',   'VPN toggle'),
            ('A',   'Audio output'),
            ('M',   'Mic mute'),
            ('N',   'Night light'),
            ('D',   'Do not disturb'),
            ('X',   'Settings'),
        ]),
    ],
]


# ── Widget builders ───────────────────────────────────────────────────────────

def _build_block(title: str, binds: list[tuple[str, str]]) -> Gtk.Box:
    """One block = heading + boxed-list with one row per keybind."""
    vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    vbox.set_margin_top(8)
    vbox.set_margin_bottom(4)

    hdr = Gtk.Label(label=title)
    hdr.add_css_class('heading')
    hdr.set_xalign(0)
    vbox.append(hdr)

    listbox = Gtk.ListBox()
    listbox.set_selection_mode(Gtk.SelectionMode.NONE)
    listbox.add_css_class('boxed-list')

    for key, desc in binds:
        row = Gtk.ListBoxRow()
        row.set_activatable(False)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_margin_top(5)
        box.set_margin_bottom(5)

        key_lbl = Gtk.Label(label=key)
        key_lbl.add_css_class('monospace')
        key_lbl.add_css_class('module-chip')
        key_lbl.set_valign(Gtk.Align.CENTER)
        key_lbl.set_size_request(110, -1)

        desc_lbl = Gtk.Label(label=desc)
        desc_lbl.set_xalign(0)
        desc_lbl.set_valign(Gtk.Align.CENTER)
        desc_lbl.set_hexpand(True)

        box.append(key_lbl)
        box.append(desc_lbl)
        row.set_child(box)
        listbox.append(row)

    vbox.append(listbox)
    return vbox


def _build_content() -> Gtk.Widget:
    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    root.set_margin_top(20)
    root.set_margin_bottom(24)
    root.set_margin_start(28)
    root.set_margin_end(28)

    title = Gtk.Label(label='Keybind Reference')
    title.add_css_class('title-2')
    title.set_margin_bottom(4)
    root.append(title)

    hint = Gtk.Label(label='ESC or click outside to close')
    hint.add_css_class('dim-label')
    hint.add_css_class('caption')
    hint.set_margin_bottom(16)
    root.append(hint)

    first_group = True
    for group in _GROUPS:
        if not first_group:
            sep = Gtk.Separator()
            sep.set_margin_top(12)
            sep.set_margin_bottom(4)
            root.append(sep)
        first_group = False

        for title_txt, binds in group:
            root.append(_build_block(title_txt, binds))

    return root


# ── Application ───────────────────────────────────────────────────────────────

class KeybindHelpApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id='com.vutureland.keybind-help',
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.connect('activate', self._activate)

    def _activate(self, _):
        _BASE_CSS = os.path.join(os.path.dirname(__file__), 'style.css')

        display = Gdk.Display.get_default()
        provider = Gtk.CssProvider()
        if os.path.exists(_BASE_CSS):
            provider.load_from_path(_BASE_CSS)
        Gtk.StyleContext.add_provider_for_display(
            display, provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)

        win = Gtk.ApplicationWindow(application=self)
        win.set_title('Keybind Help')
        win.set_decorated(False)

        # Transparent click-catcher (fullscreen background → close on click)
        click_bg = Gtk.Box()
        click_bg.set_hexpand(True)
        click_bg.set_vexpand(True)
        gesture = Gtk.GestureClick.new()
        gesture.set_button(0)
        gesture.connect('pressed', lambda *_: self.quit())
        click_bg.add_controller(gesture)

        # Scrollable content card — fixed width, auto height up to screen limit
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_size_request(480, -1)
        scroll.set_max_content_height(920)
        scroll.set_propagate_natural_height(True)
        scroll.set_propagate_natural_width(False)
        scroll.set_child(_build_content())
        scroll.add_css_class('card')
        scroll.set_halign(Gtk.Align.CENTER)
        scroll.set_valign(Gtk.Align.CENTER)
        scroll.set_hexpand(False)
        scroll.set_vexpand(False)

        overlay = Gtk.Overlay()
        overlay.set_child(click_bg)
        overlay.add_overlay(scroll)
        win.set_child(overlay)

        # ESC closes
        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect('key-pressed',
                         lambda c, kv, *_: (self.quit(), True)[1]
                         if kv == Gdk.KEY_Escape else False)
        win.add_controller(key_ctrl)

        Gtk4LayerShell.init_for_window(win)
        Gtk4LayerShell.set_namespace(win, 'vutureland-keybind-help')
        Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.OVERLAY)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.LEFT,   True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.RIGHT,  True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.TOP,    True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.BOTTOM, True)
        Gtk4LayerShell.set_exclusive_zone(win, -1)
        Gtk4LayerShell.set_keyboard_mode(win, Gtk4LayerShell.KeyboardMode.EXCLUSIVE)

        win.present()

        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM,
                             lambda: (self.quit(), GLib.SOURCE_REMOVE)[1])


if __name__ == '__main__':
    KeybindHelpApp().run()
