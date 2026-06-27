#!/usr/bin/env python3
"""Vutureland Control Center — python3 main.py --panel"""

import os, sys, signal, json, time, re, datetime, atexit, subprocess

# ── LD_PRELOAD / GTK backend (before any GTK import, same as main.py) ─────────
_LIB = '/usr/lib/libgtk4-layer-shell.so'
if 'libgtk4-layer-shell' not in os.environ.get('LD_PRELOAD', ''):
    os.environ['LD_PRELOAD'] = _LIB + ':' + os.environ.get('LD_PRELOAD', '')
    os.execv(sys.executable, [sys.executable] + sys.argv)

os.environ['GDK_BACKEND'] = 'wayland'

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
gi.require_version('Gtk4LayerShell', '1.0')
from gi.repository import Gtk, Adw, Gdk, Gio, GLib, GdkPixbuf, Gtk4LayerShell

sys.path.insert(0, os.path.dirname(__file__))
from panel_player import PlayerWidget

# ── Module-level paths — identical formulae to main.py ────────────────────────

_PID_FILE = '/tmp/vutureland-panel.pid'

_CSS = os.path.join(os.path.dirname(__file__), 'style.css')

_SETTINGS_FILE = os.path.join(
    os.environ.get('VUTURELAND_USER_DIR',
                   os.path.join(os.environ.get('XDG_CONFIG_HOME',
                                               os.path.expanduser('~/.config')),
                                'vutureland')),
    'gui', 'settings.json',
)
_HISTORY_FILE = os.path.join(
    os.environ.get('VUTURELAND_USER_DIR',
                   os.path.join(os.environ.get('XDG_CONFIG_HOME',
                                               os.path.expanduser('~/.config')),
                                'vutureland')),
    'gui', 'notify-history.json',
)
_COLORS_CSS_PATH = os.path.join(
    os.environ.get('VUTURELAND_USER_DIR',
                   os.path.join(os.environ.get('XDG_CONFIG_HOME',
                                               os.path.expanduser('~/.config')),
                                'vutureland')),
    'assets', 'colors_gtk.css',
)
_COLORS_CSS_FALLBACK = os.path.join(
    os.environ.get('VUTURELAND_DIR',
                   os.path.realpath(os.path.join(os.path.dirname(__file__), '..'))),
    'assets', 'colors_gtk.css',
)
_BANNER = os.path.join(
    os.environ.get('VUTURELAND_DIR',
                   os.path.realpath(os.path.join(os.path.dirname(__file__), '..'))),
    'assets', 'icons', 'vutureland.png',
)
_LOGO_PATHS = {
    'full':   _BANNER,
    'simple': os.path.join(os.path.dirname(_BANNER), 'vuture.png'),
    'none':   None,
}
_PANEL_WIDTH = 900   # same default as main.py
_OPACITY_DIM = 0.88

_PANEL_CSS = b"""
.panel-time { font-size: 52px; font-weight: 300; }
.panel-date { opacity: 0.6; }
"""

# ── Helpers — identical to main.py ────────────────────────────────────────────

def _build_theme_css(bg_primary, bg_element, bg_active, bg_hover,
                     bo_normal, bo_active, fg_primary, fg_muted, fg_bright) -> str:
    return f"""
        .root-area    {{ background-color: {bg_primary}; }}
        .body-area    {{ background-color: {bg_element}; }}
        .content-area {{ background-color: {bg_primary}; color: {fg_primary}; }}
        .logo-bar     {{ background-color: {bg_element}; }}
        .nav-sidebar  {{ background-color: {bg_element}; }}
        .nav-btn      {{ color: {fg_muted}; }}
        .nav-btn:hover   {{ background-color: alpha({bg_active}, 0.15); color: {fg_primary}; }}
        .nav-btn:checked {{ background-color: {bg_active}; color: {fg_bright}; }}
        label, .heading, .title-1, .title-2, .title-3, .title-4 {{ color: {fg_primary}; }}
        .caption, .dim-label                                    {{ color: {fg_muted}; }}
        .bar-zone      {{ background-color: alpha({bg_element}, 0.6);
                          border-color: alpha({bo_normal}, 0.55); }}
        .module-chip   {{ background-color: {bg_element}; color: {fg_primary};
                          border-color: alpha({bo_normal}, 0.55); }}
    """

_THEME_CSS: dict[str, str] = {
    'follow': '',
    'dark':   _build_theme_css(
        bg_primary='#0d0d0d', bg_element='#1e1e1e', bg_active='#3a7bd5',
        bg_hover='#2a2a2a',   bo_normal='#505050',  bo_active='#7a7a7a',
        fg_primary='#f0f0f0', fg_muted='#bcbcbc',   fg_bright='#ffffff',
    ),
    'bright': _build_theme_css(
        bg_primary='#fafafa', bg_element='#eeeeee', bg_active='#1a73e8',
        bg_hover='#dde6f5',   bo_normal='#b0b0b0',  bo_active='#1a73e8',
        fg_primary='#101010', fg_muted='#3a3a3a',   fg_bright='#000000',
    ),
}

_BASE_CSS_PROVIDER   = None
_DESIGN_CSS_PROVIDER = None
_COLORS_CSS_PROVIDER = None


def _load_settings() -> dict:
    try:
        with open(_SETTINGS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _active_theme() -> str:
    base = os.environ.get('VUTURELAND_USER_DIR') or os.path.join(
        os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config')), 'vutureland')
    try:
        with open(os.path.join(base, 'active-theme')) as f:
            return f.read().strip() or 'miboro'
    except Exception:
        return 'miboro'


def _reload_design_theme():
    if _DESIGN_CSS_PROVIDER is None:
        return
    css = os.path.join(os.path.dirname(__file__), 'themes', _active_theme() + '.css')
    try:
        if os.path.exists(css):
            _DESIGN_CSS_PROVIDER.load_from_path(css)
        else:
            _DESIGN_CSS_PROVIDER.load_from_data(b'')
    except Exception:
        pass


def _load_logo(path: str, height: int) -> GdkPixbuf.Pixbuf | None:
    if not path or not os.path.exists(path):
        return None
    try:
        pb = GdkPixbuf.Pixbuf.new_from_file(path)
        if pb.get_has_alpha():
            w, h = pb.get_width(), pb.get_height()
            rs = pb.get_rowstride()
            p  = pb.get_pixels()
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
    except Exception:
        return None

# ── PID management ────────────────────────────────────────────────────────────

def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _running_pid() -> int | None:
    try:
        pid = int(open(_PID_FILE).read().strip())
        return pid if _pid_alive(pid) else None
    except (OSError, ValueError):
        return None


def _acquire_pid_lock() -> bool:
    if _running_pid() is not None:
        return False
    with open(_PID_FILE, 'w') as f:
        f.write(str(os.getpid()))
    atexit.register(lambda: os.unlink(_PID_FILE) if os.path.exists(_PID_FILE) else None)
    return True

# ── Misc helpers ──────────────────────────────────────────────────────────────

def _spawn(*cmd):
    subprocess.Popen(list(cmd), start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _pkg_dir() -> str:
    return os.environ.get('VUTURELAND_DIR',
                          os.path.realpath(os.path.join(os.path.dirname(__file__), '..')))


def _rel_time(ts: float) -> str:
    diff = time.time() - ts
    if diff < 60:    return 'gerade eben'
    if diff < 3600:  return f'vor {int(diff // 60)} Min.'
    if diff < 86400: return f'vor {int(diff // 3600)} Std.'
    return f'vor {int(diff // 86400)} T.'

# ── Panel content widgets ─────────────────────────────────────────────────────

class ClockWidget(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.set_halign(Gtk.Align.CENTER)
        self.set_margin_top(24)
        self.set_margin_bottom(16)
        self._time_lbl = Gtk.Label()
        self._time_lbl.add_css_class('panel-time')
        self.append(self._time_lbl)
        self._date_lbl = Gtk.Label()
        self._date_lbl.add_css_class('panel-date')
        self.append(self._date_lbl)
        self._tick()
        GLib.timeout_add_seconds(1, self._tick)

    def _tick(self) -> bool:
        now = datetime.datetime.now()
        self._time_lbl.set_label(now.strftime('%H:%M'))
        self._date_lbl.set_label(now.strftime('%A, %d. %B %Y'))
        return True


class SessionWidget(Adw.PreferencesGroup):
    def __init__(self, close_fn):
        super().__init__(title='Session')
        self._close = close_fn
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
            ('Sperren',     'system-lock-screen-symbolic',  self._lock),
            ('Ruhezustand', 'weather-clear-night-symbolic', self._suspend),
            ('Abmelden',    'system-log-out-symbolic',      self._logout),
            ('Neustart',    'system-reboot-symbolic',       self._reboot),
            ('Ausschalten', 'system-shutdown-symbolic',     self._shutdown),
        ]:
            btn = Gtk.Button()
            btn.add_css_class('session-btn')
            btn.set_hexpand(True)
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            inner.set_margin_top(12); inner.set_margin_bottom(12)
            img = Gtk.Image.new_from_icon_name(icon)
            img.set_pixel_size(24)
            inner.append(img)
            inner.append(Gtk.Label(label=label))
            btn.set_child(inner)
            btn.connect('clicked', handler)
            grid.insert(btn, -1)
        row = Adw.PreferencesRow()
        row.set_activatable(False)
        row.set_child(grid)
        self.add(row)

    def _lock(self, _=None):
        self._close()
        _spawn('bash', os.path.join(_pkg_dir(), 'assets', 'scripts', 'launch-hyprlock.sh'))

    def _suspend(self, _=None):
        self._close()
        _spawn('systemctl', 'suspend')

    def _logout(self, _=None):
        self._ask('Abmelden?', 'Die aktuelle Sitzung wird beendet.',
                  lambda: _spawn('hyprctl', 'dispatch', 'exit'))

    def _reboot(self, _=None):
        self._ask('Neu starten?', 'Das System wird neu gestartet.',
                  lambda: _spawn('systemctl', 'reboot'))

    def _shutdown(self, _=None):
        self._ask('Ausschalten?', 'Das System wird heruntergefahren.',
                  lambda: _spawn('systemctl', 'poweroff'))

    def _ask(self, heading: str, body: str, action):
        dialog = Adw.AlertDialog(heading=heading, body=body)
        dialog.add_response('cancel',  'Abbrechen')
        dialog.add_response('confirm', heading.rstrip('?'))
        dialog.set_response_appearance('confirm', Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_close_response('cancel')
        dialog.connect('response',
                       lambda d, r: (self._close(), action()) if r == 'confirm' else None)
        dialog.present(self.get_root())


class HistoryWidget(Adw.PreferencesGroup):
    """Notification history group.

    The empty state uses a plain Adw.PreferencesRow with a centred label —
    transparent background is achieved via the .notif-empty-row CSS override
    in _PANEL_CSS so it doesn't look like an interactive card row.
    """
    def __init__(self):
        super().__init__(title='Benachrichtigungen')
        self._rows: list[Adw.ActionRow] = []

        clear_btn = Gtk.Button(label='Leeren')
        clear_btn.add_css_class('flat')
        clear_btn.add_css_class('pill')
        clear_btn.set_valign(Gtk.Align.CENTER)
        clear_btn.connect('clicked', self._clear)
        self.set_header_suffix(clear_btn)

        self._empty_row = Adw.PreferencesRow()
        self._empty_row.add_css_class('notif-empty-row')
        self._empty_row.set_activatable(False)
        lbl = Gtk.Label(label='Keine Benachrichtigungen')
        lbl.add_css_class('dim-label')
        lbl.set_halign(Gtk.Align.CENTER)
        lbl.set_margin_top(14)
        lbl.set_margin_bottom(14)
        self._empty_row.set_child(lbl)
        self.add(self._empty_row)

        self.load()

    def load(self):
        for row in self._rows:
            self.remove(row)
        self._rows.clear()

        history = []
        try:
            with open(_HISTORY_FILE) as f:
                history = json.load(f)
        except Exception:
            pass

        self._empty_row.set_visible(not history)
        for entry in history[:40]:
            row = self._make_row(entry)
            self.add(row)
            self._rows.append(row)

    def _make_row(self, entry: dict) -> Adw.ActionRow:
        summary = entry.get('summary', '') or '(kein Titel)'
        body    = re.sub(r'<[^>]+>', '', entry.get('body', '') or '')
        app     = entry.get('app_name', '') or ''
        ts      = float(entry.get('timestamp', 0))
        urgency = int(entry.get('urgency', 1))

        row = Adw.ActionRow(title=summary)
        if body:
            row.set_subtitle(body)
            row.set_subtitle_lines(2)
        row.set_activatable(False)

        if urgency != 1:
            dot = Gtk.Label()
            dot.set_use_markup(True)
            dot.set_markup(
                f'<span foreground="{"#a0a0a0" if urgency == 0 else "#e01b24"}">●</span>')
            dot.set_valign(Gtk.Align.CENTER)
            row.add_prefix(dot)

        parts = [p for p in (app, _rel_time(ts) if ts else '') if p]
        if parts:
            meta = Gtk.Label(label=' · '.join(parts))
            meta.add_css_class('dim-label')
            meta.add_css_class('caption')
            meta.set_valign(Gtk.Align.CENTER)
            row.add_suffix(meta)

        return row

    def _clear(self, _=None):
        try:
            with open(_HISTORY_FILE, 'w') as f:
                json.dump([], f)
        except Exception:
            pass
        self.load()

# ── Panel window — structural clone of MainWindow ─────────────────────────────

class PanelWindow(Gtk.ApplicationWindow):
    """Identical layout to MainWindow; sidebar ghosted; content is panel widgets."""

    _PLACE_CLASSES = [
        'place-left-top', 'place-left-center', 'place-left-bottom',
        'place-right-top', 'place-right-center', 'place-right-bottom',
    ]

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title('Vutureland Panel')
        self.set_decorated(False)
        self._settings = _load_settings()

        try:
            mon  = Gdk.Display.get_default().get_monitors().get_item(0)
            geom = mon.get_geometry()
            self._monitor_w, self._monitor_h = geom.width, geom.height
        except Exception:
            self._monitor_w, self._monitor_h = 1920, 1080

        # Theme override provider — same priority slot as MainWindow
        self._theme_provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), self._theme_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)

        # ── Panel content (replaces ViewStack) ────────────────────────────────
        page = Adw.PreferencesPage()
        page.set_hexpand(True)
        page.set_vexpand(True)
        page.add(PlayerWidget())
        page.add(SessionWidget(self.hide))
        self._history = HistoryWidget()
        page.add(self._history)

        content_inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content_inner.add_css_class('content-area')
        content_inner.set_hexpand(True)
        content_inner.set_vexpand(True)
        content_inner.append(ClockWidget())
        content_inner.append(page)

        content_wrap = Gtk.ScrolledWindow()
        content_wrap.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        content_wrap.set_propagate_natural_width(False)
        content_wrap.set_propagate_natural_height(False)
        content_wrap.set_min_content_width(0)
        content_wrap.set_min_content_height(0)
        content_wrap.set_hexpand(True)
        content_wrap.set_vexpand(True)
        content_wrap.set_child(content_inner)
        content_wrap.add_css_class('content-scroll')
        self._content_wrap = content_wrap

        # ── Ghost sidebar — same width as main GUI, invisible & non-interactive
        show_labels = self._settings.get('sidebar_labels', False)
        self._sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._sidebar.add_css_class('nav-sidebar')
        self._sidebar.set_hexpand(False)
        self._sidebar.set_size_request(160 if show_labels else 56, -1)
        self._sidebar.set_opacity(0.0)
        self._sidebar.set_sensitive(False)

        # ── Body — identical to MainWindow ────────────────────────────────────
        body = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        body.add_css_class('body-area')
        body.set_hexpand(True)
        body.set_vexpand(True)
        body.append(self._sidebar)
        body.append(content_wrap)
        self._body = body

        # ── Root — identical to MainWindow ────────────────────────────────────
        self._root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self._root.add_css_class('root-area')
        self._root.set_halign(Gtk.Align.START)
        self._root.set_valign(Gtk.Align.END)
        self._root.set_hexpand(False)
        self._root.set_vexpand(False)
        self._root.set_overflow(Gtk.Overflow.HIDDEN)
        self._root.append(self._build_swap_bar())   # above logo — dezent strip
        self._root.append(self._build_banner())
        self._root.append(body)

        # ── Click-catcher + overlay — identical to MainWindow ─────────────────
        click_catcher = Gtk.Box()
        click_catcher.set_hexpand(True)
        click_catcher.set_vexpand(True)
        gesture = Gtk.GestureClick.new()
        gesture.set_button(0)
        gesture.connect('pressed', lambda *_: self.hide())
        click_catcher.add_controller(gesture)

        overlay = Gtk.Overlay()
        overlay.set_child(click_catcher)
        overlay.add_overlay(self._root)
        self.set_child(overlay)

        # Apply saved size / placement / opacity / theme (same as MainWindow.__init__)
        w_pct = self._settings.get(
            'panel_width_pct',
            max(20, min(90, _PANEL_WIDTH * 100 // self._monitor_w)))
        self._apply_size(w_pct, self._settings.get('panel_height_pct', 100))
        self._apply_placement(self._settings.get('panel_side',   'left'),
                              self._settings.get('panel_valign', 'bottom'))
        if self._settings.get('opacity_enabled', False):
            self._root.set_opacity(self._settings.get('opacity_value', _OPACITY_DIM))
        saved_theme = self._settings.get('menu_theme', 'follow')
        if saved_theme != 'follow':
            self._apply_theme(saved_theme)

        self.connect('close-request', lambda w: w.hide() or True)

        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect('key-pressed', lambda _c, kv, _kc, _s:
                         (self.hide(), True) if kv == Gdk.KEY_Escape else False)
        self.add_controller(key_ctrl)

    def refresh(self):
        if self._history:
            self._history.load()

    # ── Banner — copy of MainWindow._build_banner / _render_banner ────────────

    def _build_banner(self) -> Gtk.Box:
        self._banner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self._banner.add_css_class('logo-bar')
        self._banner.set_hexpand(True)
        self._banner.set_vexpand(False)
        self._render_banner(self._settings.get('logo_variant', 'full'))
        return self._banner

    def _render_banner(self, variant: str):
        child = self._banner.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._banner.remove(child)
            child = nxt
        if variant == 'none':
            self._banner.set_visible(False)
            return
        self._banner.set_visible(True)
        path = _LOGO_PATHS.get(variant, _LOGO_PATHS['full'])
        pb = _load_logo(path, height=64) if path else None
        if not pb:
            return
        texture = Gdk.Texture.new_for_pixbuf(pb)
        pic = Gtk.Picture.new_for_paintable(texture)
        pic.set_content_fit(Gtk.ContentFit.SCALE_DOWN)
        pic.set_halign(Gtk.Align.CENTER)
        pic.set_valign(Gtk.Align.CENTER)
        pic.set_hexpand(True)
        pic.set_vexpand(False)
        pic.set_can_shrink(True)
        pic.set_size_request(-1, pb.get_height())
        self._banner.append(pic)

    # ── Swap strip — dezent, above logo, full area clickable ──────────────────

    def _build_swap_bar(self) -> Gtk.Box:
        bar = Gtk.Box()
        bar.add_css_class('logo-bar')
        bar.set_hexpand(True)
        icon = Gtk.Image.new_from_icon_name('go-up-symbolic')
        icon.set_pixel_size(14)
        icon.add_css_class('dim-label')
        icon.set_halign(Gtk.Align.CENTER)
        icon.set_hexpand(True)
        icon.set_margin_top(5)
        icon.set_margin_bottom(5)
        bar.append(icon)
        gesture = Gtk.GestureClick.new()
        gesture.set_button(1)
        gesture.connect('released', lambda *_: self._swap_to_settings())
        bar.add_controller(gesture)
        bar.set_cursor(Gdk.Cursor.new_from_name('pointer'))
        bar.set_tooltip_text('Einstellungen öffnen')
        return bar

    # ── Layout helpers — copy of MainWindow ───────────────────────────────────

    def _apply_placement(self, side: str, valign: str):
        side   = side   if side   in ('left', 'right')           else 'left'
        valign = valign if valign in ('top', 'center', 'bottom') else 'bottom'

        self._root.set_halign(Gtk.Align.START if side == 'left' else Gtk.Align.END)
        self._root.set_valign({'top':    Gtk.Align.START,
                               'center': Gtk.Align.CENTER,
                               'bottom': Gtk.Align.END}[valign])
        for cls in self._PLACE_CLASSES:
            self._root.remove_css_class(cls)
        self._root.add_css_class(f'place-{side}-{valign}')

        # Mirror ghost sidebar to the screen-edge side (keeps border-radius correct)
        if side == 'left':
            self._body.reorder_child_after(self._sidebar, None)
        else:
            self._body.reorder_child_after(self._sidebar, self._content_wrap)

    def _apply_size(self, w_pct: int, h_pct: int):
        w = int(self._monitor_w * w_pct / 100)
        h = int(self._monitor_h * h_pct / 100)
        self._root.set_size_request(w, h)
        self._root.queue_resize()

    def _apply_theme(self, theme: str):
        css = _THEME_CSS.get(theme, '')
        self._theme_provider.load_from_string(css)
        if _BASE_CSS_PROVIDER is not None:
            try:
                _BASE_CSS_PROVIDER.load_from_path(_CSS)
            except Exception:
                pass
        style_mgr = Adw.StyleManager.get_default()
        if theme == 'bright':
            style_mgr.set_color_scheme(Adw.ColorScheme.FORCE_LIGHT)
        elif theme == 'dark':
            style_mgr.set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        else:
            style_mgr.set_color_scheme(Adw.ColorScheme.DEFAULT)

    def _swap_to_settings(self):
        self.hide()
        _spawn(sys.executable, os.path.join(os.path.dirname(__file__), 'main.py'))

# ── Application — mirrors VuturelandSettings._activate CSS loading ─────────────

class PanelApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id='com.vutureland.panel',
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.connect('activate', self._activate)
        self.connect('shutdown', lambda _:
                     os.unlink(_PID_FILE) if os.path.exists(_PID_FILE) else None)
        self.hold()

    def _activate(self, _):
        global _BASE_CSS_PROVIDER, _DESIGN_CSS_PROVIDER, _COLORS_CSS_PROVIDER

        display = Gdk.Display.get_default()

        # Force Adwaita icon theme so all symbolic icons render (same as main.py)
        Gtk.Settings.get_default().set_property('gtk-icon-theme-name', 'Adwaita')

        # 1. Wallust color palette
        _COLORS_CSS_PROVIDER = Gtk.CssProvider()
        if os.path.exists(_COLORS_CSS_PATH):
            _COLORS_CSS_PROVIDER.load_from_path(_COLORS_CSS_PATH)
        elif os.path.exists(_COLORS_CSS_FALLBACK):
            _COLORS_CSS_PROVIDER.load_from_path(_COLORS_CSS_FALLBACK)
        Gtk.StyleContext.add_provider_for_display(
            display, _COLORS_CSS_PROVIDER, Gtk.STYLE_PROVIDER_PRIORITY_USER)

        # 2. Base style.css
        _BASE_CSS_PROVIDER = Gtk.CssProvider()
        _BASE_CSS_PROVIDER.load_from_path(_CSS)
        Gtk.StyleContext.add_provider_for_display(
            display, _BASE_CSS_PROVIDER, Gtk.STYLE_PROVIDER_PRIORITY_USER)

        # 3. Active design theme (gui/themes/<active>.css)
        _DESIGN_CSS_PROVIDER = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            display, _DESIGN_CSS_PROVIDER, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        _reload_design_theme()

        # 4. Panel-specific CSS (clock font; empty-row transparent bg)
        panel_prov = Gtk.CssProvider()
        panel_prov.load_from_data(
            _PANEL_CSS +
            b"\nrow.notif-empty-row { background: transparent; box-shadow: none; }\n"
        )
        Gtk.StyleContext.add_provider_for_display(
            display, panel_prov, Gtk.STYLE_PROVIDER_PRIORITY_USER + 2)

        win = PanelWindow(application=self)
        self._win = win

        Gtk4LayerShell.init_for_window(win)
        Gtk4LayerShell.set_namespace(win, 'vutureland-panel')
        Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.OVERLAY)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.LEFT,   True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.RIGHT,  True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.TOP,    True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.BOTTOM, True)
        Gtk4LayerShell.set_exclusive_zone(win, -1)
        Gtk4LayerShell.set_keyboard_mode(win, Gtk4LayerShell.KeyboardMode.ON_DEMAND)

        def _toggle():
            show = not win.get_visible()
            if show:
                win.refresh()
            win.set_visible(show)
            return GLib.SOURCE_CONTINUE

        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, _toggle)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM,
                             lambda: (self.quit(), GLib.SOURCE_REMOVE)[1])

        win.present()
        if os.environ.get('VUTURELAND_START_HIDDEN') == '1':
            win.hide()

# ── Entry point ───────────────────────────────────────────────────────────────

def _handle_flags():
    args = sys.argv[1:]

    if '-e' in args or '--end' in args:
        pid = _running_pid()
        if pid is not None:
            os.kill(pid, signal.SIGTERM)
        sys.exit(0)

    if '-t' in args or '--toggle' in args:
        sys.argv = [a for a in sys.argv if a not in ('-t', '--toggle')]
        pid = _running_pid()
        if pid is not None:
            os.kill(pid, signal.SIGUSR1)
            sys.exit(0)

    if '-d' in args or '--daemon' in args:
        sys.argv = [a for a in sys.argv if a not in ('-d', '--daemon')]
        if _running_pid() is not None:
            sys.exit(0)
        os.environ['VUTURELAND_START_HIDDEN'] = '1'
        if not _acquire_pid_lock():
            sys.exit(0)
        return

    pid = _running_pid()
    if pid is not None:
        os.kill(pid, signal.SIGUSR1)
        sys.exit(0)
    if not _acquire_pid_lock():
        sys.exit(0)


if __name__ == '__main__':
    _handle_flags()
    PanelApp().run()
