from __future__ import annotations
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw

import os, signal, threading, subprocess


def _vtl() -> str:
    return os.environ.get('VUTURELAND_DIR') or os.path.realpath(
        os.path.join(os.path.dirname(__file__), '../..'))


def _restart_notify() -> None:
    try:
        pid = int(open('/tmp/vutureland-notify.pid').read().strip())
        os.kill(pid, signal.SIGTERM)
    except Exception:
        pass
    gui = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'main.py')
    threading.Thread(
        target=lambda: subprocess.run(
            ['python3', gui, '--notify', '--daemon'], capture_output=True),
        daemon=True,
    ).start()


class NotificationsPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__()
        self._home_cb = None
        self._build_ui()

    def set_home_callback(self, cb):
        self._home_cb = cb

    # ── UI ───────────────────────────────────────────────────────────────────

    def _build_ui(self):
        self.add(self._build_back_group())

        group = Adw.PreferencesGroup(
            title='Notification Daemon',
            description='Vutureland handles notifications natively. '
                        'Position and appearance are configured on the OSD page.',
        )

        restart_btn = Gtk.Button(label='Restart Notification Daemon')
        restart_btn.add_css_class('pill')
        restart_btn.set_halign(Gtk.Align.CENTER)
        restart_btn.connect('clicked', lambda _: _restart_notify())

        row = Adw.PreferencesRow()
        row.set_activatable(False)
        row.add_css_class('flat')
        row.set_child(restart_btn)
        group.add(row)
        self.add(group)

    def _build_back_group(self) -> Adw.PreferencesGroup:
        img = Gtk.Image.new_from_icon_name('go-up-symbolic')
        img.set_halign(Gtk.Align.CENTER)
        img.set_hexpand(True)

        row = Adw.PreferencesRow()
        row.set_activatable(False)
        row.add_css_class('back-btn-row')
        row.set_child(img)
        gesture = Gtk.GestureClick()
        gesture.connect('released', lambda g, n, x, y: self._home_cb and self._home_cb())
        row.add_controller(gesture)

        group = Adw.PreferencesGroup()
        group.add_css_class('back-btn-group')
        group.add(row)
        return group
