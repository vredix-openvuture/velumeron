from __future__ import annotations
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw, GLib

import os, subprocess


def _clean_env() -> dict:
    env = dict(os.environ)
    env.pop('LD_PRELOAD', None)
    return env


def _launch_swaync_script() -> str:
    vtl = os.environ.get('VUTURELAND_DIR') or os.path.realpath(
        os.path.join(os.path.dirname(__file__), '../..'))
    return os.path.join(vtl, 'assets', 'scripts', 'launch-swaync.sh')


class NotificationsPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__()
        self._values_cb = None
        self._build_ui()

    def set_values_callback(self, cb, margin_top_pct: int = 10, width_pct: int = 23):
        self._margin_scale.set_value(margin_top_pct)
        self._width_scale.set_value(width_pct)
        self._values_cb = cb

    # ── UI ───────────────────────────────────────────────────────────────────

    def _build_ui(self):
        group = Adw.PreferencesGroup(
            title='Control Center',
            description='Position and size of the notification center, relative to the focused monitor.',
        )

        self._margin_scale = self._add_slider_row(group, 'Top margin (%)', 0, 50, 10)
        self._width_scale  = self._add_slider_row(group, 'Width (%)',      10, 70, 23)
        self.add(group)

        # Apply
        apply_group = Adw.PreferencesGroup()
        apply_btn = Gtk.Button(label='Apply & Restart swaync')
        apply_btn.add_css_class('suggested-action')
        apply_btn.add_css_class('pill')
        apply_btn.set_halign(Gtk.Align.CENTER)
        apply_btn.connect('clicked', self._on_apply)
        apply_group.add(apply_btn)
        self.add(apply_group)

    def _add_slider_row(self, group, title, lo, hi, default) -> Gtk.Scale:
        row = Adw.ActionRow(title=title)
        sc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, lo, hi, 1)
        sc.set_size_request(240, -1)
        sc.set_draw_value(True)
        sc.set_value_pos(Gtk.PositionType.RIGHT)
        sc.set_value(default)
        sc.set_valign(Gtk.Align.CENTER)
        sc.set_hexpand(True)
        sc.connect('value-changed', self._on_slider_changed)
        row.add_suffix(sc)
        group.add(row)
        return sc

    # ── Handlers ─────────────────────────────────────────────────────────────

    def _on_slider_changed(self, _):
        if self._values_cb:
            self._values_cb(int(self._margin_scale.get_value()),
                            int(self._width_scale.get_value()))

    def _on_apply(self, _):
        try:
            subprocess.Popen(['bash', _launch_swaync_script()], env=_clean_env())
        except Exception:
            pass
