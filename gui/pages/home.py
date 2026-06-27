from __future__ import annotations
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
gi.require_version('GdkPixbuf', '2.0')

from gi.repository import Gtk, Adw, GLib, Gdk, GdkPixbuf

import os, re, subprocess, threading, shutil, json, time

from models.waybar import active_bar_for_monitor
from constants import POWERMODE_SH
from design import list_designs, current_design, apply_design
from panel_player import PlayerWidget


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


def _user_dir() -> str:
    return os.environ.get('VUTURELAND_USER_DIR') or os.path.join(
        os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config')),
        'vutureland')


def _notify_history_file() -> str:
    return os.path.join(_user_dir(), 'gui', 'notify-history.json')


def _rel_time(ts: float) -> str:
    diff = time.time() - ts
    if diff < 60:    return 'gerade eben'
    if diff < 3600:  return f'vor {int(diff // 60)} Min.'
    if diff < 86400: return f'vor {int(diff // 3600)} Std.'
    return f'vor {int(diff // 86400)} T.'


class HomePage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._apply_cb  = None
        self._notify_cb = None
        self._updating_power = False
        # Stack so Network/Bluetooth open as in-panel subpages (a separate window
        # can't be used under the layer-shell panel).
        self._stack = Gtk.Stack()
        self._stack.set_vexpand(True)
        self._stack.add_named(self._build_main(), 'main')
        self.append(self._stack)
        GLib.idle_add(self._refresh_status)
        GLib.idle_add(self._load_power_profile)
        # Refresh the active-style label + wallpaper preview every time the page
        # is shown, so it tracks live theme/wallpaper changes.
        self.connect('map', lambda _w: (self._refresh_current(),
                                        self._load_power_profile(),
                                        self._refresh_notify()) and False)

    def set_apply_callback(self, cb):
        self._apply_cb = cb

    def set_notify_callback(self, cb):
        self._notify_cb = cb

    # ── Notification panel ───────────────────────────────────────────────────────

    def _build_notify_group(self) -> Adw.PreferencesGroup:
        grp = Adw.PreferencesGroup()
        self._notify_row = Adw.ActionRow(
            title='Keine Benachrichtigungen',
            icon_name='notification-new-symbolic',
        )
        self._notify_row.set_activatable(True)
        self._notify_row.add_suffix(
            Gtk.Image.new_from_icon_name('go-next-symbolic'))
        self._notify_row.connect('activated',
                                 lambda _r: self._notify_cb and self._notify_cb())
        grp.add(self._notify_row)
        return grp

    def _refresh_notify(self):
        row = getattr(self, '_notify_row', None)
        if row is None:
            return False
        try:
            with open(_notify_history_file()) as f:
                history = json.load(f)
        except Exception:
            history = []

        if not history:
            row.set_title('Keine Benachrichtigungen')
            row.set_subtitle('')
            return False

        entry   = history[0]
        summary = entry.get('summary', '') or '(kein Titel)'
        app     = entry.get('app_name', '') or ''
        ts      = float(entry.get('timestamp', 0))
        body    = re.sub(r'<[^>]+>', '', entry.get('body', '') or '')

        row.set_title(summary)
        sub_parts = [p for p in (app, _rel_time(ts) if ts else '', body) if p]
        row.set_subtitle(' · '.join(sub_parts[:2]))
        return False

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
        """Return a path suitable for the preview image.
        For static wallpapers this is the file itself; for live (video)
        wallpapers wallust writes a deleted /tmp frame, so we fall back to the
        pre-generated thumbnail from the wallpaper-thumbs cache."""
        colors = os.path.join(_user_dir(), 'hypr.lua', 'colors.lua')
        wp = None
        try:
            with open(colors) as f:
                for line in f:
                    m = re.match(r'\s*wallpaper\s*=\s*"(.+)"', line)
                    if m:
                        wp = m.group(1)
                        break
        except OSError:
            pass

        if wp and os.path.exists(wp):
            return wp

        # colors.lua holds a temp path that was deleted (video wallpaper).
        # Find the video currently shown by mpvpaper and use its cached thumb.
        thumb = self._video_wallpaper_thumb()
        return thumb if thumb else wp

    @staticmethod
    def _video_wallpaper_thumb() -> str | None:
        """Return the cached thumbnail for the video wallpaper on the focused monitor."""
        cache = os.path.join(
            os.environ.get('XDG_CACHE_HOME', os.path.expanduser('~/.cache')),
            'vutureland', 'wallpaper-thumbs')
        try:
            focused_mon = None
            mons = subprocess.run(['hyprctl', 'monitors', '-j'],
                                  capture_output=True, text=True, timeout=2).stdout
            for mon in json.loads(mons):
                if mon.get('focused'):
                    focused_mon = mon['name']
                    break

            r = subprocess.run(['pgrep', '-fa', 'mpvpaper'],
                               capture_output=True, text=True, timeout=2)
            for line in r.stdout.splitlines():
                parts = line.split()
                # mpvpaper ... MONITOR /path/to/video.ext — file is always last
                for i, part in enumerate(parts):
                    if re.search(r'\.(mp4|webm|mkv|avi|mov)$', part, re.IGNORECASE):
                        video = part
                        monitor = parts[i - 1] if i > 0 else None
                        if focused_mon and monitor and monitor != focused_mon:
                            continue
                        stem = os.path.splitext(os.path.basename(video))[0]
                        t = os.path.join(cache, stem + '.png')
                        if os.path.exists(t):
                            return t
        except Exception:
            pass
        return None

    # Preview size — a bit smaller again.
    _PREVIEW_W = 168
    _PREVIEW_H = 52

    def _build_current_group(self) -> Adw.PreferencesGroup:
        grp = Adw.PreferencesGroup()
        self._current_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self._current_box.set_margin_top(4); self._current_box.set_margin_bottom(8)
        self._current_box.set_margin_start(4); self._current_box.set_margin_end(4)
        grp.add(self._current_box)
        self._refresh_current()
        return grp

    def _refresh_current(self):
        """Rebuild the wallpaper preview with the theme name overlaid on it
        (called on show so it tracks the live theme). Skipped when nothing
        changed — decoding the wallpaper PNG every open is what made the panel
        slow to appear on clients with large wallpapers."""
        box = getattr(self, '_current_box', None)
        if box is None:
            return

        style = current_design() or self._active_style()
        wp = self._active_wallpaper()
        try:
            mtime = os.path.getmtime(wp) if wp and os.path.exists(wp) else 0
        except OSError:
            mtime = 0
        key = (style, wp, mtime)
        if key == getattr(self, '_current_key', None) and box.get_first_child():
            return                       # unchanged — keep the built preview
        self._current_key = key

        child = box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            box.remove(child)
            child = nxt

        pic = None
        if wp and os.path.exists(wp):
            try:
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                    wp, self._PREVIEW_W, -1, True)
                pic = Gtk.Picture.new_for_paintable(Gdk.Texture.new_for_pixbuf(pb))
                pic.set_content_fit(Gtk.ContentFit.COVER)
                pic.set_size_request(-1, self._PREVIEW_H)
            except Exception:
                pic = None
        if pic is None:
            pic = Gtk.Image.new_from_icon_name('image-x-generic')
            pic.set_pixel_size(32)
            pic.set_size_request(-1, self._PREVIEW_H)

        frame = Gtk.Frame()
        frame.add_css_class('wp-frame')
        frame.set_overflow(Gtk.Overflow.HIDDEN)
        frame.set_child(pic)
        frame.set_size_request(self._PREVIEW_W, self._PREVIEW_H)

        # Theme name overlaid in the centre of the image — white with a black
        # drop shadow so it stays legible on any wallpaper. Clicking it opens a
        # design picker; choosing a design themes every app (waybar/hypr/swaync/
        # gui), exactly as selecting it on the waybar page used to.
        overlay = Gtk.Overlay()
        overlay.set_child(frame)
        overlay.set_halign(Gtk.Align.CENTER)

        name_lbl = Gtk.Label(label=style or 'No active bar')
        name_lbl.add_css_class('theme-overlay-name')

        btn = Gtk.MenuButton()
        btn.add_css_class('flat')
        btn.add_css_class('theme-overlay-btn')
        btn.set_child(name_lbl)
        btn.set_halign(Gtk.Align.CENTER)
        btn.set_valign(Gtk.Align.CENTER)
        btn.set_tooltip_text('Choose design')
        btn.set_popover(self._design_popover(style))
        overlay.add_overlay(btn)
        box.append(overlay)

    def _design_popover(self, current: str | None) -> Gtk.Popover:
        pop = Gtk.Popover()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.set_margin_top(4); box.set_margin_bottom(4)
        box.set_margin_start(4); box.set_margin_end(4)
        designs = list_designs()
        if not designs:
            box.append(Gtk.Label(label='No designs found'))
        for d in designs:
            b = Gtk.Button(label=d)
            b.add_css_class('flat')
            b.set_halign(Gtk.Align.FILL)
            if d == current:
                b.add_css_class('suggested-action')
            b.connect('clicked',
                      lambda _w, dd=d, p=pop: (p.popdown(), self._choose_design(dd)))
            box.append(b)
        pop.set_child(box)
        return pop

    def _choose_design(self, design: str):
        apply_design(design)
        self._refresh_current()

    # ── Power mode ──────────────────────────────────────────────────────────────

    @staticmethod
    def _read_power_profile() -> str:
        try:
            gm = subprocess.run(['bash', POWERMODE_SH, '--gamemode'],
                                capture_output=True, text=True).stdout.strip()
            if gm == 'active':
                return 'gamemode'
            prof = subprocess.run(['bash', POWERMODE_SH, '--active'],
                                  capture_output=True, text=True).stdout.strip()
            return prof if prof else 'balanced'
        except Exception:
            return 'balanced'

    def _build_power_row(self) -> Adw.PreferencesRow:
        btn_box = Gtk.Box(spacing=0, margin_top=4, margin_bottom=8,
                          margin_start=8, margin_end=8)
        btn_box.add_css_class('linked')
        btn_box.set_hexpand(True)

        self._power_btns: dict[str, Gtk.ToggleButton] = {}
        for key, label in [
            ('power-saver', 'Power Saver'),
            ('balanced',    'Balanced'),
            ('performance', 'Performance'),
            ('gamemode',    'Game Mode'),
        ]:
            btn = Gtk.ToggleButton(label=label)
            btn.set_hexpand(True)
            btn.connect('toggled', self._on_power_toggled, key)
            btn_box.append(btn)
            self._power_btns[key] = btn

        row = Adw.PreferencesRow()
        row.set_activatable(False)
        row.set_child(btn_box)
        return row

    def _load_power_profile(self):
        def _work():
            profile = self._read_power_profile()
            GLib.idle_add(self._apply_power_ui, profile)
        threading.Thread(target=_work, daemon=True).start()

    def _apply_power_ui(self, profile: str):
        self._updating_power = True
        for key, btn in self._power_btns.items():
            btn.set_active(key == profile)
        self._updating_power = False
        return False

    def _on_power_toggled(self, btn, key: str):
        if not btn.get_active() or getattr(self, '_updating_power', False):
            return
        self._updating_power = True
        for k, b in self._power_btns.items():
            if k != key and b.get_active():
                b.set_active(False)
        self._updating_power = False

        flag = {
            'power-saver': '--set_powersaver',
            'balanced':    '--set_balanced',
            'performance': '--set_performance',
            'gamemode':    '--set_gamemode',
        }.get(key)
        if flag:
            threading.Thread(
                target=lambda: subprocess.run(['bash', POWERMODE_SH, flag],
                                              capture_output=True),
                daemon=True,
            ).start()

    # ── UI ────────────────────────────────────────────────────────────────────

    def _build_main(self) -> Adw.PreferencesPage:
        page = Adw.PreferencesPage()
        # ── Current look: active waybar style + wallpaper preview ──
        page.add(self._build_current_group())

        # ── Latest notification ──
        page.add(self._build_notify_group())

        # Connectivity + power mode (merged, no heading)
        conn = Adw.PreferencesGroup()

        # Network row
        self._net_row = Adw.ActionRow(
            title='Network',
            subtitle='—',
            icon_name='network-wireless-symbolic',
        )
        net_btn = Gtk.Button(label='Open')
        net_btn.add_css_class('flat')
        net_btn.set_valign(Gtk.Align.CENTER)
        net_btn.connect('clicked', lambda _: self._open_network_page())
        self._net_row.add_suffix(net_btn)
        self._net_row.set_activatable(True)
        self._net_row.connect('activated', lambda r: self._open_network_page())
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
        bt_btn.connect('clicked', lambda _: self._open_bluetooth_page())
        self._bt_row.add_suffix(bt_btn)
        conn.add(self._bt_row)
        conn.add(self._build_power_row())
        page.add(conn)

        # Session group — a wrapping FlowBox so the buttons reflow to fewer
        # columns as the panel narrows (instead of pinning a wide minimum width).
        session = Adw.PreferencesGroup()
        grid_row = Adw.PreferencesRow()
        grid_row.set_activatable(False)
        grid = Gtk.FlowBox()
        grid.set_selection_mode(Gtk.SelectionMode.NONE)
        grid.set_homogeneous(True)
        grid.set_min_children_per_line(1)
        grid.set_max_children_per_line(5)
        grid.set_row_spacing(8)
        grid.set_column_spacing(8)
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
            btn.set_hexpand(True)
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            inner.set_margin_top(12); inner.set_margin_bottom(12)
            img = Gtk.Image.new_from_icon_name(icon)
            img.set_pixel_size(24)
            inner.append(img)
            lbl = Gtk.Label(label=label)
            inner.append(lbl)
            btn.set_child(inner)
            btn.connect('clicked', handler)
            grid.insert(btn, -1)
        grid_row.set_child(grid)
        session.add(grid_row)
        page.add(session)

        page.add(PlayerWidget())
        return page

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

    # ── In-panel subpage helpers ───────────────────────────────────────────────

    def _stack_set(self, name: str, widget):
        old = self._stack.get_child_by_name(name)
        if old is not None:
            self._stack.remove(old)
        self._stack.add_named(widget, name)
        self._stack.set_visible_child_name(name)

    def _subpage_header(self, title: str, on_refresh=None) -> Gtk.Box:
        h = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                    margin_start=12, margin_end=12, margin_top=10, margin_bottom=6)
        back = Gtk.Button(icon_name='go-previous-symbolic')
        back.add_css_class('flat')
        back.connect('clicked', lambda _: (self._stack.set_visible_child_name('main'),
                                           self._refresh_status()))
        h.append(back)
        lbl = Gtk.Label(label=title)
        lbl.add_css_class('title-4')
        lbl.set_hexpand(True)
        lbl.set_halign(Gtk.Align.START)
        h.append(lbl)
        if on_refresh is not None:
            rb = Gtk.Button(icon_name='view-refresh-symbolic')
            rb.add_css_class('flat')
            rb.connect('clicked', lambda _: on_refresh())
            h.append(rb)
        return h

    @staticmethod
    def _nm_split(line: str) -> list[str]:
        # nmcli -t escapes ':' inside fields as '\:'
        return [f.replace('\\:', ':') for f in re.split(r'(?<!\\):', line)]

    # ══ Network subpage ════════════════════════════════════════════════════════

    def _open_network_page(self):
        self._wifi_rows, self._vpn_rows = [], []
        page = Adw.PreferencesPage()

        cur = Adw.PreferencesGroup(title='Current connection')
        self._net_cur_row = Adw.ActionRow(title=self._net_status_text() or '—')
        cur.add(self._net_cur_row)
        page.add(cur)

        self._wifi_group = Adw.PreferencesGroup(title='Wi-Fi')
        page.add(self._wifi_group)
        self._vpn_group = Adw.PreferencesGroup(title='VPN')
        page.add(self._vpn_group)

        self._net_status_lbl = Gtk.Label(label='', xalign=0)
        self._net_status_lbl.add_css_class('dim-label')
        self._net_status_lbl.set_margin_start(14)
        self._net_status_lbl.set_margin_end(14)
        self._net_status_lbl.set_wrap(True)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(self._subpage_header('Network',
                                        on_refresh=lambda: self._refresh_network(rescan=True)))
        box.append(self._net_status_lbl)
        box.append(page)
        self._stack_set('network', box)
        self._refresh_network()              # cached on open — only Reload rescans

    def _refresh_network(self, rescan=False):
        for r in self._wifi_rows:
            self._wifi_group.remove(r)
        for r in self._vpn_rows:
            self._vpn_group.remove(r)
        self._wifi_rows, self._vpn_rows = [], []
        if not shutil.which('nmcli'):
            self._add_info(self._wifi_group, self._wifi_rows, 'nmcli not installed')
            return
        if rescan:
            self._add_info(self._wifi_group, self._wifi_rows, 'Scanning…')

        def _work():
            wifi = self._scan_wifi(rescan)
            vpns = self._list_vpn()
            cur  = self._net_status_text()
            GLib.idle_add(self._populate_network, wifi, vpns, cur)
        threading.Thread(target=_work, daemon=True).start()

    @staticmethod
    def _add_info(group, rows, text):
        row = Adw.ActionRow(title=text)
        group.add(row)
        rows.append(row)

    def _populate_network(self, wifi, vpns, cur):
        self._net_cur_row.set_title(cur or '—')
        for r in self._wifi_rows:
            self._wifi_group.remove(r)
        self._wifi_rows = []
        for net in wifi:
            row = self._wifi_row(net)
            self._wifi_group.add(row)
            self._wifi_rows.append(row)
        if not wifi:
            self._add_info(self._wifi_group, self._wifi_rows, 'No networks found')
        for v in vpns:
            row = self._vpn_row(v)
            self._vpn_group.add(row)
            self._vpn_rows.append(row)
        if not vpns:
            self._add_info(self._vpn_group, self._vpn_rows, 'No VPN connections')
        return False

    def _active_wifi(self) -> str | None:
        """Name (≈ SSID) of the active wireless connection, or None. More reliable
        than the ACTIVE column of `dev wifi list`, which can be empty when wired
        is the default route."""
        try:
            r = subprocess.run(['nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show', '--active'],
                               capture_output=True, text=True, timeout=6, env=_clean_env())
            for line in r.stdout.splitlines():
                p = self._nm_split(line)
                if len(p) >= 2 and 'wireless' in p[1]:
                    return p[0]
        except Exception:
            pass
        return None

    def _scan_wifi(self, rescan=False) -> list:
        try:
            r = subprocess.run(
                ['nmcli', '-t', '-f', 'ACTIVE,SSID,SIGNAL,SECURITY',
                 'dev', 'wifi', 'list', '--rescan', 'yes' if rescan else 'no'],
                capture_output=True, text=True,
                timeout=25 if rescan else 8, env=_clean_env())
        except Exception:
            return []
        active_name = self._active_wifi()
        best = {}
        for line in r.stdout.splitlines():
            p = self._nm_split(line)
            if len(p) < 4 or not p[1]:
                continue
            ssid, sig = p[1], p[2]
            try:
                sig = int(sig)
            except ValueError:
                sig = 0
            net = {'ssid': ssid, 'signal': sig,
                   'secured': bool(p[3].strip()) and p[3].strip() != '--',
                   'active': p[0] == 'yes' or (active_name is not None and ssid == active_name)}
            # Dedup by SSID across multiple APs: the active one always wins;
            # otherwise keep the strongest signal. (Bug fix: a stronger inactive
            # BSSID must not overwrite the active one, or "Connected" is lost.)
            cur = best.get(ssid)
            if cur is None:
                best[ssid] = net
            elif net['active'] and not cur['active']:
                best[ssid] = net
            elif not cur['active'] and net['signal'] > cur['signal']:
                best[ssid] = net
        return sorted(best.values(), key=lambda n: (not n['active'], -n['signal']))

    def _wifi_row(self, net):
        # Visible Connect/Disconnect button (like Bluetooth). The active network
        # shows ✓ + "Connected". Secured networks keep an expandable "edit" area
        # (chevron) to type/replace the password.
        if net['active']:
            row = Adw.ActionRow(title=net['ssid'], subtitle='Connected')
            row.add_prefix(Gtk.Image.new_from_icon_name('object-select-symbolic'))
            # Shows the state ("Connected"), default colour like the Bluetooth
            # connected button (no accent); clicking it disconnects.
            btn = Gtk.Button(label='Connected', valign=Gtk.Align.CENTER)
            btn.connect('clicked', lambda b, s=net['ssid']: self._wifi_disconnect(s, b))
            row.add_suffix(btn)
            return row

        if not net['secured']:
            row = Adw.ActionRow(title=net['ssid'], subtitle=f"Signal {net['signal']}% · open")
            btn = Gtk.Button(label='Connect', valign=Gtk.Align.CENTER)
            btn.add_css_class('suggested-action')
            btn.connect('clicked', lambda b, s=net['ssid'], r=row: self._wifi_connect(s, False, b, r))
            row.add_suffix(btn)
            return row

        row = Adw.ExpanderRow(title=net['ssid'], subtitle=f"Signal {net['signal']}% · secured")
        btn = Gtk.Button(label='Connect', valign=Gtk.Align.CENTER)
        btn.add_css_class('suggested-action')
        btn.connect('clicked', lambda b, s=net['ssid'], r=row: self._wifi_connect(s, True, b, r))
        row.add_suffix(btn)
        try:
            pw = Adw.PasswordEntryRow(title='Password')
        except Exception:
            pw = Adw.EntryRow(title='Password')
        row.add_row(pw)
        act = Adw.ActionRow(subtitle='Connect using this password')
        pbtn = Gtk.Button(label='Connect', valign=Gtk.Align.CENTER)
        pbtn.add_css_class('suggested-action')
        pbtn.connect('clicked', lambda b, s=net['ssid'], e=pw: self._wifi_connect_pw(s, e.get_text(), b))
        act.add_suffix(pbtn)
        row.add_row(act)
        return row

    def _busy(self, btn, _text='…'):
        """Replace a button's label with a spinner while an action runs."""
        if btn is not None:
            btn.set_sensitive(False)
            sp = Gtk.Spinner()
            sp.start()
            btn.set_child(sp)

    def _unbusy(self, btn, label):
        if btn is not None:
            btn.set_child(None)
            btn.set_label(label)
            btn.set_sensitive(True)

    def _net_set_status(self, text):
        if getattr(self, '_net_status_lbl', None):
            self._net_status_lbl.set_text(text)

    def _nm_connect(self, ssid, password):
        args = ['nmcli', 'dev', 'wifi', 'connect', ssid]
        if password:
            args += ['password', password]
        try:
            r = subprocess.run(args, capture_output=True, text=True,
                               env=_clean_env(), timeout=60)
            return {'ok': r.returncode == 0,
                    'msg': (r.stderr.strip() or r.stdout.strip() or '')}
        except subprocess.TimeoutExpired:
            return {'ok': False, 'msg': 'Timed out — check the password'}
        except Exception as e:
            return {'ok': False, 'msg': str(e)}

    def _wifi_connect(self, ssid, secured, btn=None, row=None):
        self._busy(btn)
        self._net_set_status(f'Connecting to {ssid}…')
        def _do():
            r = self._nm_connect(ssid, None)   # try saved profile / open network
            if r['ok']:
                GLib.idle_add(self._net_done, 'Connected to ' + ssid)
            elif secured:
                GLib.idle_add(self._wifi_need_pw, btn, row)   # needs a password
            else:
                GLib.idle_add(self._net_done, r['msg'] or 'Connection failed')
        threading.Thread(target=_do, daemon=True).start()

    def _wifi_need_pw(self, btn, row):
        self._net_set_status('This network needs a password — enter it, then Connect.')
        self._unbusy(btn, 'Connect')
        if row is not None:
            try:
                row.set_expanded(True)
            except Exception:
                pass
        return False

    def _wifi_connect_pw(self, ssid, pw, btn=None):
        self._busy(btn)
        self._net_set_status(f'Connecting to {ssid}…')
        def _do():
            r = self._nm_connect(ssid, pw or None)
            GLib.idle_add(self._net_done,
                          'Connected to ' + ssid if r['ok'] else (r['msg'] or 'Connection failed'))
        threading.Thread(target=_do, daemon=True).start()

    def _wifi_disconnect(self, ssid, btn=None):
        self._busy(btn, 'Disconnecting…')
        self._net_set_status(f'Disconnecting from {ssid}…')
        def _do():
            try:
                r = subprocess.run(['nmcli', 'connection', 'down', 'id', ssid],
                                   capture_output=True, text=True, env=_clean_env(), timeout=20)
                msg = 'Disconnected' if r.returncode == 0 else (r.stderr.strip() or 'Disconnect failed')
            except Exception as e:
                msg = str(e)
            GLib.idle_add(self._net_done, msg)
        threading.Thread(target=_do, daemon=True).start()

    def _net_done(self, msg):
        self._net_set_status(msg)
        self._refresh_network()
        self._refresh_status()
        return False

    def _list_vpn(self) -> list:
        try:
            r = subprocess.run(
                ['nmcli', '-t', '-f', 'NAME,TYPE,STATE', 'connection', 'show'],
                capture_output=True, text=True, timeout=8, env=_clean_env())
        except Exception:
            return []
        out = []
        for line in r.stdout.splitlines():
            p = self._nm_split(line)
            if len(p) < 2:
                continue
            if p[1] in ('vpn', 'wireguard'):
                out.append({'name': p[0],
                            'up': len(p) > 2 and p[2] == 'activated'})
        return sorted(out, key=lambda v: v['name'].lower())

    def _vpn_row(self, v):
        row = Adw.ActionRow(title=v['name'], subtitle='VPN')
        sw = Gtk.Switch(valign=Gtk.Align.CENTER)
        sw.set_active(v['up'])
        sw.connect('notify::active', lambda s, _p, n=v['name']: self._vpn_toggle(n, s.get_active()))
        row.add_suffix(sw)
        return row

    def _vpn_toggle(self, name, up):
        def _do():
            try:
                subprocess.run(['nmcli', 'connection', 'up' if up else 'down', name],
                               capture_output=True, env=_clean_env(), timeout=30)
            except Exception:
                pass
            GLib.idle_add(self._refresh_status)
        threading.Thread(target=_do, daemon=True).start()

    # ══ Bluetooth subpage ══════════════════════════════════════════════════════

    def _open_bluetooth_page(self):
        self._bt_rows = []
        page = Adw.PreferencesPage()

        ctrl = Adw.PreferencesGroup(title='Bluetooth')
        pwr = Adw.ActionRow(title='Power')
        self._bt_page_switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        self._bt_page_switch.set_active(self._bt_powered())
        self._bt_page_switch.connect('notify::active', self._on_bt_page_power)
        pwr.add_suffix(self._bt_page_switch)
        ctrl.add(pwr)
        scan = Adw.ActionRow(title='Scan for devices', subtitle='Discovers nearby devices for ~10s')
        scan_btn = Gtk.Button(label='Scan')
        scan_btn.set_valign(Gtk.Align.CENTER)
        scan_btn.connect('clicked', lambda _: self._bt_scan())
        scan.add_suffix(scan_btn)
        ctrl.add(scan)
        page.add(ctrl)

        self._bt_group = Adw.PreferencesGroup(title='Devices')
        page.add(self._bt_group)

        self._bt_status_lbl = Gtk.Label(label='', xalign=0)
        self._bt_status_lbl.add_css_class('dim-label')
        self._bt_status_lbl.set_margin_start(14)
        self._bt_status_lbl.set_margin_end(14)
        self._bt_status_lbl.set_wrap(True)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(self._subpage_header('Bluetooth', on_refresh=self._refresh_bt))
        box.append(self._bt_status_lbl)
        box.append(page)
        self._stack_set('bluetooth', box)
        self._refresh_bt()

    def _on_bt_page_power(self, switch, _):
        target = 'on' if switch.get_active() else 'off'
        def _do():
            subprocess.run(['bluetoothctl', 'power', target],
                           capture_output=True, env=_clean_env())
            GLib.idle_add(self._refresh_bt)
            GLib.idle_add(self._refresh_status)
        threading.Thread(target=_do, daemon=True).start()

    def _refresh_bt(self):
        for r in self._bt_rows:
            self._bt_group.remove(r)
        self._bt_rows = []
        if not shutil.which('bluetoothctl'):
            self._add_info(self._bt_group, self._bt_rows, 'bluetoothctl not installed')
            return
        self._add_info(self._bt_group, self._bt_rows, 'Loading…')
        def _work():
            devices = self._list_bt_devices()
            GLib.idle_add(self._populate_bt, devices)
        threading.Thread(target=_work, daemon=True).start()

    def _populate_bt(self, devices):
        for r in self._bt_rows:
            self._bt_group.remove(r)
        self._bt_rows = []
        for d in devices:
            row = self._bt_device_row(d)
            self._bt_group.add(row)
            self._bt_rows.append(row)
        if not devices:
            self._add_info(self._bt_group, self._bt_rows, 'No devices — try Scan')
        return False

    def _list_bt_devices(self) -> list:
        def _names(arg):
            try:
                r = subprocess.run(['bluetoothctl', 'devices', arg] if arg
                                   else ['bluetoothctl', 'devices'],
                                   capture_output=True, text=True, timeout=4, env=_clean_env())
                out = {}
                for ln in r.stdout.splitlines():
                    m = re.match(r'Device (\S+) (.+)', ln)
                    if m:
                        out[m.group(1)] = m.group(2)
                return out
            except Exception:
                return {}
        alld = _names('')
        connected = set(_names('Connected').keys())
        paired = set(_names('Paired').keys())
        result = []
        for mac, name in sorted(alld.items(), key=lambda kv: kv[1].lower()):
            result.append({'mac': mac, 'name': name,
                           'connected': mac in connected, 'paired': mac in paired})
        return result

    def _bt_device_row(self, d):
        sub = 'Connected' if d['connected'] else ('Paired' if d['paired'] else 'Available')
        row = Adw.ActionRow(title=d['name'], subtitle=sub)
        btn = Gtk.Button(label='Disconnect' if d['connected'] else 'Connect')
        btn.set_valign(Gtk.Align.CENTER)
        if not d['connected']:
            btn.add_css_class('suggested-action')
        btn.connect('clicked', lambda b, m=d['mac'], c=d['connected'], p=d['paired'], n=d['name']:
                    self._bt_action(m, c, p, n, b))
        row.add_suffix(btn)
        return row

    def _bt_action(self, mac, connected, paired, name='', btn=None):
        self._busy(btn, 'Disconnecting…' if connected else 'Connecting…')
        if getattr(self, '_bt_status_lbl', None):
            self._bt_status_lbl.set_text(
                ('Disconnecting from ' if connected else 'Connecting to ') + (name or mac) + '…')
        def _run(args, t):
            try:
                return subprocess.run(['bluetoothctl', *args], capture_output=True,
                                      text=True, env=_clean_env(), timeout=t)
            except Exception as e:
                class _R: returncode = 1; stdout = ''; stderr = str(e)
                return _R()
        def _do():
            if connected:
                r = _run(['disconnect', mac], 15)
                ok = 'Successful' in (r.stdout or '') or r.returncode == 0
                msg = ('Disconnected' if ok else
                       (r.stderr.strip() or r.stdout.strip() or 'Disconnect failed'))
            else:
                if not paired:
                    _run(['pair', mac], 25)
                    _run(['trust', mac], 5)
                r = _run(['connect', mac], 25)
                ok = 'Connection successful' in (r.stdout or '')
                msg = ('Connected' if ok else
                       (r.stderr.strip() or (r.stdout.strip().splitlines() or ['Connection failed'])[-1]))
            GLib.idle_add(self._bt_done, msg)
        threading.Thread(target=_do, daemon=True).start()

    def _bt_done(self, msg):
        if getattr(self, '_bt_status_lbl', None):
            self._bt_status_lbl.set_text(msg)
        self._refresh_bt()
        self._refresh_status()
        return False

    def _bt_scan(self):
        def _do():
            try:
                subprocess.run(['bluetoothctl', '--timeout', '10', 'scan', 'on'],
                               capture_output=True, env=_clean_env(), timeout=15)
            except Exception:
                pass
            GLib.idle_add(self._refresh_bt)
        threading.Thread(target=_do, daemon=True).start()

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
