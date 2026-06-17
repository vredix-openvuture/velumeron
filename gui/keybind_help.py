#!/usr/bin/env python3
"""Vutureland Keybind Help — floating cheatsheet (SUPER+SHIFT+/)"""

import os, sys, signal, atexit

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
# Structure: list of (tag, blocks).  tag=None → main layer, else submap name.
# Groups are separated by a visual divider when showing all.
# Each block: (title, [(key, desc), ...])

_GROUPS: list[tuple[str | None, list[tuple[str, list[tuple[str, str]]]]]] = [
    # ── Main layer ────────────────────────────────────────────────────────
    (None, [
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
            (',',        'Submap leader  → SUPER+W/A/S'),
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
            ('F',             'Fullscreen'),
            ('M',             'Maximize'),
            ('P',             'Pin'),
            ('H / J / K / L', 'Resize'),
        ]),
        ('SUPER + CTRL', [
            ('L',   'Lockscreen'),
            ('Q',   'Session menu'),
            ('C',   'Force kill'),
            ('P',   'Bitwarden'),
            ('ESC', 'Quit Hyprland'),
        ]),
    ]),
    # ── Window submap ─────────────────────────────────────────────────────
    ('window', [
        ('Window submap  (SUPER + , → SUPER + W)', [
            ('SUPER + H / J / K / L',       'Focus direction'),
            ('SUPER + C',                   'Close'),
            ('SUPER + F',                   'Float toggle'),
            ('SUPER + T',                   'Transparency'),
            ('SUPER + P',                   'Pseudo-tile'),
            ('SUPER + G',                   'Group toggle'),
            ('SUPER + N / SHIFT + N',       'Group next / prev'),
            ('SUPER + D / M / O',           'Layout Dwindle / Master / Split'),
            ('SUPER + Space',               'Center window'),
            ('SUPER + Tab',                 'Window switcher'),
            ('SUPER + 1 – 9',               'Move to workspace'),
            ('SUPER + SHIFT + /',           'Submap help'),
            ('ESC / Enter',                 'Exit submap'),
        ]),
        ('Window + SHIFT', [
            ('SUPER + SHIFT + H / J / K / L', 'Move window in tiling'),
        ]),
        ('Window + ALT', [
            ('SUPER + ALT + H / J / K / L', 'Resize'),
            ('SUPER + ALT + F',             'Fullscreen'),
            ('SUPER + ALT + M',             'Maximize'),
            ('SUPER + ALT + P',             'Pin'),
        ]),
    ]),
    # ── Apps submap ───────────────────────────────────────────────────────
    ('apps', [
        ('Apps submap  (SUPER + , → SUPER + A)', [
            ('SUPER + T',         'Terminal'),
            ('SUPER + W',         'Browser'),
            ('SUPER + E',         'File manager'),
            ('SUPER + N',         'Notifications'),
            ('SUPER + M',         'Messenger'),
            ('SUPER + O',         'Notes'),
            ('SUPER + P',         'Music player'),
            ('SUPER + C',         'Clock'),
            ('SUPER + I',         'Mail'),
            ('SUPER + K',         'Calendar'),
            ('SUPER + D',         'Tasks'),
            ('SUPER + V',         'Editor'),
            ('SUPER + Space',     'Launcher'),
            ('SUPER + SHIFT + /', 'Submap help'),
            ('ESC / Enter',       'Exit submap'),
        ]),
    ]),
    # ── System submap ─────────────────────────────────────────────────────
    ('system', [
        ('System submap  (SUPER + , → SUPER + S)', [
            ('SUPER + W',         'Wi-Fi menu'),
            ('SUPER + B',         'Bluetooth menu'),
            ('SUPER + V',         'VPN toggle'),
            ('SUPER + A',         'Audio output'),
            ('SUPER + M',         'Mic mute'),
            ('SUPER + N',         'Night light'),
            ('SUPER + D',         'Do not disturb'),
            ('SUPER + X',         'Settings'),
            ('SUPER + SHIFT + /', 'Submap help'),
            ('ESC / Enter',       'Exit submap'),
        ]),
    ]),
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


_SUBMAP_TITLES = {
    'window': 'Window Submap',
    'apps':   'Apps Submap',
    'system': 'System Submap',
}


def _build_content(submap: str | None = None) -> Gtk.Widget:
    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    root.set_margin_top(20)
    root.set_margin_bottom(24)
    root.set_margin_start(28)
    root.set_margin_end(28)

    heading = _SUBMAP_TITLES.get(submap, 'Keybind Reference') if submap else 'Keybind Reference'
    title_lbl = Gtk.Label(label=heading)
    title_lbl.add_css_class('title-2')
    title_lbl.set_margin_bottom(4)
    root.append(title_lbl)

    hint_txt = 'c or click outside to close'
    hint = Gtk.Label(label=hint_txt)
    hint.add_css_class('dim-label')
    hint.add_css_class('caption')
    hint.set_margin_bottom(16)
    root.append(hint)

    groups = [(tag, blocks) for tag, blocks in _GROUPS if tag == submap] \
             if submap else list(_GROUPS)

    first_group = True
    for _tag, blocks in groups:
        if not first_group:
            sep = Gtk.Separator()
            sep.set_margin_top(12)
            sep.set_margin_bottom(4)
            root.append(sep)
        first_group = False

        for title_txt, binds in blocks:
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

        # Extra CSS: card background matches the GUI's dark window colour
        extra = Gtk.CssProvider()
        extra.load_from_string(
            '.keybind-card { background-color: @window_bg_color;'
            ' border-radius: 12px;'
            ' border: 1px solid @borders; }')
        Gtk.StyleContext.add_provider_for_display(
            display, extra, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)

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

        submap = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None

        # Scrollable content card — fixed width, auto height up to screen limit
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_size_request(480, -1)
        scroll.set_max_content_height(920)
        scroll.set_propagate_natural_height(True)
        scroll.set_propagate_natural_width(False)
        scroll.set_child(_build_content(submap))
        scroll.add_css_class('keybind-card')
        scroll.set_halign(Gtk.Align.CENTER)
        scroll.set_valign(Gtk.Align.CENTER)
        scroll.set_hexpand(False)
        scroll.set_vexpand(False)

        overlay = Gtk.Overlay()
        overlay.set_child(click_bg)
        overlay.add_overlay(scroll)
        win.set_child(overlay)

        def _on_key(_ctrl, kv, _kc, _state):
            if kv == Gdk.KEY_c:
                self.quit()
                return True
            return False

        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect('key-pressed', _on_key)
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


def _pid_lock(submap: str | None) -> bool:
    """Return True if we acquired the lock, False if another instance is alive."""
    suffix   = f'-{submap}' if submap else ''
    pid_file = f'/tmp/vutureland-khp{suffix}.pid'
    try:
        existing = int(open(pid_file).read())
        os.kill(existing, 0)        # raises if process gone
        return False                # already running — bail out
    except (OSError, ValueError, FileNotFoundError):
        pass
    with open(pid_file, 'w') as f:
        f.write(str(os.getpid()))
    atexit.register(lambda: os.unlink(pid_file) if os.path.exists(pid_file) else None)
    return True


if __name__ == '__main__':
    _submap = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None
    if not _pid_lock(_submap):
        sys.exit(0)
    KeybindHelpApp().run()
