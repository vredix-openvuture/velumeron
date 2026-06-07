from __future__ import annotations
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
gi.require_version('GdkPixbuf', '2.0')

from gi.repository import Gtk, Adw, GLib, Gdk, GdkPixbuf

import os, subprocess, threading, shutil, json

from models.waybar import active_bar_for_monitor


def _clean_env() -> dict:
    env = dict(os.environ)
    env.pop('LD_PRELOAD', None)
    return env


def _run_async(argv: list[str]):
    threading.Thread(
        target=lambda: subprocess.run(argv, env=_clean_env(),
                                      capture_output=True),
        daemon=False,
    ).start()


def _vtl() -> str:
    return os.environ.get('VUTURELAND_DIR') or os.path.realpath(
        os.path.join(os.path.dirname(__file__), '../..'))


class HomePage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__()
        self._apply_cb = None
        self._build_ui()
        GLib.idle_add(self._refresh_status)

    def set_apply_callback(self, cb):
        self._apply_cb = cb

    # ── Current look (waybar style + wallpaper preview) ─────────────────────────

    @staticmethod
    def _monitor_names() -> list[str]:
        try:
            mons = json.loads(subprocess.run(
                ['hyprctl', 'monitors', '-j'], capture_output=True, text=True).stdout)
            focused = [m['name'] for m in mons if m.get('focused')]
            others  = [m['name'] for m in mons if not m.get('focused')]
            return focused + others
        except Exception:
            return []

    def _active_style(self) -> str | None:
        for mon in self._monitor_names():
            active = active_bar_for_monitor(mon)
            if active:
                design, style, _pos = active
                return design or style
        return None

    def _active_wallpaper(self) -> str | None:
        names = self._monitor_names()
        try:
            lines = subprocess.run(['awww', 'query'], capture_output=True,
                                   text=True).stdout.splitlines()
        except Exception:
            return None
        def _img(line):
            return line.split('image:', 1)[1].strip() if 'image:' in line else None
        for mon in names:                      # prefer the focused monitor
            for line in lines:
                if f'{mon}:' in line:
                    p = _img(line)
                    if p:
                        return p
        for line in lines:                     # otherwise any image
            p = _img(line)
            if p:
                return p
        return None

    def _build_current_group(self) -> Adw.PreferencesGroup:
        grp = Adw.PreferencesGroup()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(4); box.set_margin_bottom(8)
        box.set_margin_start(4); box.set_margin_end(4)

        style = self._active_style()
        lbl = Gtk.Label(label=style or 'No active bar')
        lbl.add_css_class('title-3')
        lbl.set_halign(Gtk.Align.START)
        box.append(lbl)

        child = None
        wp = self._active_wallpaper()
        if wp and os.path.exists(wp):
            try:
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(wp, 520, -1, True)
                pic = Gtk.Picture.new_for_paintable(Gdk.Texture.new_for_pixbuf(pb))
                pic.set_content_fit(Gtk.ContentFit.COVER)
                pic.set_size_request(-1, 150)
                child = pic
            except Exception:
                child = None
        if child is None:
            child = Gtk.Image.new_from_icon_name('image-x-generic')
            child.set_pixel_size(48)
            child.set_size_request(-1, 150)

        frame = Gtk.Frame()
        frame.add_css_class('wp-frame')
        frame.set_overflow(Gtk.Overflow.HIDDEN)
        frame.set_child(child)
        box.append(frame)

        grp.add(box)
        return grp

    # ── UI ────────────────────────────────────────────────────────────────────

    def _build_ui(self):
        # ── Current look: active waybar style + wallpaper preview ──
        self.add(self._build_current_group())

        # Connectivity group
        conn = Adw.PreferencesGroup(title='Connectivity')

        # Network row
        self._net_row = Adw.ActionRow(
            title='Network',
            subtitle='—',
            icon_name='network-wireless-symbolic',
        )
        net_btn = Gtk.Button(label='Open')
        net_btn.add_css_class('flat')
        net_btn.set_valign(Gtk.Align.CENTER)
        net_btn.connect('clicked', self._on_open_network)
        self._net_row.add_suffix(net_btn)
        conn.add(self._net_row)

        # Bluetooth row
        self._bt_row = Adw.ActionRow(
            title='Bluetooth',
            subtitle='—',
            icon_name='bluetooth-symbolic',
        )
        self._bt_switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        self._bt_switch.connect('notify::active', self._on_bt_toggled)
        self._bt_row.add_suffix(self._bt_switch)
        bt_btn = Gtk.Button(label='Open')
        bt_btn.add_css_class('flat')
        bt_btn.set_valign(Gtk.Align.CENTER)
        bt_btn.connect('clicked', self._on_open_bluetooth)
        self._bt_row.add_suffix(bt_btn)
        conn.add(self._bt_row)
        self.add(conn)

        # Session group
        session = Adw.PreferencesGroup(title='Session')
        grid_row = Adw.PreferencesRow()
        grid_row.set_activatable(False)
        grid = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL,
                       spacing=10, homogeneous=True)
        grid.set_margin_start(8);  grid.set_margin_end(8)
        grid.set_margin_top(8);    grid.set_margin_bottom(8)
        for label, icon, handler in [
            ('Lock',     'system-lock-screen-symbolic', self._on_lock),
            ('Suspend',  'weather-clear-night-symbolic', self._on_suspend),
            ('Logout',   'system-log-out-symbolic',     self._on_logout),
            ('Reboot',   'system-reboot-symbolic',      self._on_reboot),
            ('Shutdown', 'system-shutdown-symbolic',    self._on_shutdown),
        ]:
            btn = Gtk.Button()
            btn.add_css_class('session-btn')
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            inner.set_margin_top(12); inner.set_margin_bottom(12)
            img = Gtk.Image.new_from_icon_name(icon)
            img.set_pixel_size(24)
            inner.append(img)
            lbl = Gtk.Label(label=label)
            inner.append(lbl)
            btn.set_child(inner)
            btn.connect('clicked', handler)
            grid.append(btn)
        grid_row.set_child(grid)
        session.add(grid_row)
        self.add(session)

    # ── Status polling ───────────────────────────────────────────────────────

    def _refresh_status(self):
        bt_on = self._bt_powered()
        self._bt_switch.handler_block_by_func(self._on_bt_toggled)
        self._bt_switch.set_active(bt_on)
        self._bt_switch.handler_unblock_by_func(self._on_bt_toggled)
        self._bt_row.set_subtitle(self._bt_status_text(bt_on))
        self._net_row.set_subtitle(self._net_status_text())
        return False

    def _bt_powered(self) -> bool:
        try:
            r = subprocess.run(['bluetoothctl', 'show'],
                               capture_output=True, text=True, timeout=2,
                               env=_clean_env())
            return any('Powered: yes' in ln for ln in r.stdout.splitlines())
        except Exception:
            return False

    def _bt_status_text(self, powered: bool) -> str:
        if not powered:
            return 'Off'
        try:
            r = subprocess.run(['bluetoothctl', 'devices', 'Connected'],
                               capture_output=True, text=True, timeout=2,
                               env=_clean_env())
            names = [ln.split(' ', 2)[2] for ln in r.stdout.splitlines()
                     if ln.startswith('Device')]
            if names:
                return f'Connected: {", ".join(names)}'
        except Exception:
            pass
        return 'On — no devices connected'

    def _net_status_text(self) -> str:
        if not shutil.which('nmcli'):
            return '—'
        try:
            r = subprocess.run(
                ['nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show', '--active'],
                capture_output=True, text=True, timeout=2, env=_clean_env())
            lines = [l for l in r.stdout.splitlines() if l.strip()]
            if not lines:
                return 'Disconnected'
            parts = lines[0].split(':')
            name = parts[0] if parts else '?'
            typ  = parts[1] if len(parts) > 1 else ''
            kind = 'Wi-Fi'    if 'wireless' in typ \
              else 'Ethernet' if 'ethernet' in typ else typ
            return f'{kind} — {name}'
        except Exception:
            return '—'

    # ── Actions ──────────────────────────────────────────────────────────────

    def _on_bt_toggled(self, switch, _):
        target = 'on' if switch.get_active() else 'off'
        def _do():
            subprocess.run(['bluetoothctl', 'power', target],
                           env=_clean_env(), capture_output=True)
            GLib.idle_add(self._refresh_status)
        threading.Thread(target=_do, daemon=False).start()

    def _on_open_network(self, _):
        if shutil.which('nm-connection-editor'):
            if self._apply_cb: self._apply_cb()
            _run_async(['nm-connection-editor'])
        elif shutil.which('kitty'):
            if self._apply_cb: self._apply_cb()
            _run_async(['kitty', '--class', 'no_float', '-e', 'nmtui'])

    def _on_open_bluetooth(self, _):
        path = os.path.join(_vtl(), 'rofi', 'assets', 'bluetooth.sh')
        if os.path.exists(path):
            if self._apply_cb: self._apply_cb()
            _run_async(['bash', path])

    def _on_lock(self, _):
        if self._apply_cb: self._apply_cb()
        _run_async(['bash', os.path.join(_vtl(), 'assets', 'scripts', 'launch-hyprlock.sh')])

    def _on_suspend(self, _):
        if self._apply_cb: self._apply_cb()
        _run_async(['systemctl', 'suspend'])

    def _on_logout(self, _):
        _run_async(['hyprctl', 'dispatch', 'exit'])

    def _on_reboot(self, _):
        _run_async(['systemctl', 'reboot'])

    def _on_shutdown(self, _):
        _run_async(['systemctl', 'poweroff'])
