from __future__ import annotations
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw


class SettingsPage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=20)
        self._opacity_cb = None
        self._build_ui()

    def set_opacity_callback(self, cb, initial: bool = False):
        self._opacity_switch.set_active(initial)   # fires before cb is set → no-op
        self._opacity_cb = cb

    def _build_ui(self):
        title = Gtk.Label(label='Settings')
        title.add_css_class('title-2')
        title.set_halign(Gtk.Align.START)
        self.append(title)

        sec = Gtk.Label(label='Appearance')
        sec.add_css_class('heading')
        sec.set_halign(Gtk.Align.START)
        sec.set_margin_top(8)
        self.append(sec)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.set_margin_top(6)

        txt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        txt.set_hexpand(True)
        lbl = Gtk.Label(label='Transparency')
        lbl.set_halign(Gtk.Align.START)
        sub = Gtk.Label(label='Show the blurred desktop through the panel')
        sub.add_css_class('caption')
        sub.add_css_class('dim-label')
        sub.set_halign(Gtk.Align.START)
        txt.append(lbl)
        txt.append(sub)
        row.append(txt)

        self._opacity_switch = Gtk.Switch()
        self._opacity_switch.set_valign(Gtk.Align.CENTER)
        self._opacity_switch.connect('notify::active', self._on_opacity_toggled)
        row.append(self._opacity_switch)

        self.append(row)

    def _on_opacity_toggled(self, switch, _):
        if self._opacity_cb:
            self._opacity_cb(switch.get_active())
