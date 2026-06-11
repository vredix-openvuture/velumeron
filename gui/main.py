#!/usr/bin/env python3
"""Vutureland Settings — GTK4/Adwaita layer-shell panel"""

import os, sys, signal, json

# ── Flag handling (before GTK / LD_PRELOAD) ───────────────────────────────────
_PID_FILE = '/tmp/vutureland-settings.pid'

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

# -h / --help
if '-h' in sys.argv or '--help' in sys.argv:
    print(
        "Usage: python3 main.py [FLAG]\n"
        "\n"
        "  (no flag)      Start the panel and show the window\n"
        "  -d, --daemon   Start as background daemon (window hidden);\n"
        "                 no-op if the daemon is already running\n"
        "  -t, --toggle   Show the panel if hidden, hide it if visible;\n"
        "                 starts the daemon if it is not running yet\n"
        "  -e, --end      Stop the running daemon\n"
        "  -h, --help     Show this help message\n"
    )
    sys.exit(0)

# -e / --end: stop the running daemon
if '-e' in sys.argv or '--end' in sys.argv:
    pid = _running_pid()
    if pid is not None:
        os.kill(pid, signal.SIGTERM)
    sys.exit(0)

# -d / --daemon: start hidden; no-op if process already running
if '-d' in sys.argv or '--daemon' in sys.argv:
    sys.argv = [a for a in sys.argv if a not in ('-d', '--daemon')]
    if _running_pid() is not None:
        sys.exit(0)                           # already running — nothing to do
    os.environ['VUTURELAND_START_HIDDEN'] = '1'

# -t / --toggle: toggle visibility of running instance, or start if not running
if '-t' in sys.argv or '--toggle' in sys.argv:
    sys.argv = [a for a in sys.argv if a not in ('-t', '--toggle')]
    pid = _running_pid()
    if pid is not None:
        os.kill(pid, signal.SIGUSR1)
        sys.exit(0)

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

from pages.home          import HomePage
from pages.wallpaper     import WallpaperPage
from pages.hyprland      import HyprlandPage
from pages.waybar        import WaybarPage
from pages.lockscreen    import LockscreenPage
from pages.notifications import NotificationsPage
from pages.settings      import SettingsPage

_CSS           = os.path.join(os.path.dirname(__file__), 'style.css')
_BANNER        = os.path.join(
    os.environ.get('VUTURELAND_DIR',
                   os.path.realpath(os.path.join(os.path.dirname(__file__), '..'))),
    'assets', 'icons', 'vutureland.png'
)
_LOGO_PATHS = {
    'full':   _BANNER,
    'simple': os.path.join(os.path.dirname(_BANNER), 'vuture.png'),
    'none':   None,
}
_SETTINGS_FILE = os.path.join(
    os.environ.get('VUTURELAND_USER_DIR',
                   os.path.join(os.environ.get('XDG_CONFIG_HOME',
                                               os.path.expanduser('~/.config')),
                                'vutureland')),
    'gui', 'settings.json'
)
_PANEL_WIDTH   = 900           # fallback when no panel_width_pct saved
_OPACITY_DIM   = 0.88          # default opacity slider position

def _build_theme_css(bg_primary, bg_element, bg_active, bg_hover,
                     bo_normal, bo_active, fg_primary, fg_muted, fg_bright) -> str:
    # Direct rules instead of @define-color overrides — those don't reliably
    # cross provider boundaries when the base style.css is parsed elsewhere.
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
        .palette-chip  {{ background-color: {bg_element}; color: {fg_primary};
                          border-color: alpha({bo_normal}, 0.45); }}
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

# Base style.css provider lives at module scope so `_apply_theme` can reload it
# after the @define-color overrides change — @color refs only resolve at parse.
_BASE_CSS_PROVIDER   = None
# Provider for the active design's GUI theme overrides (gui/themes/<active>.css).
_DESIGN_CSS_PROVIDER = None
# Provider for the wallust-generated color palette. Reloaded when the file
# changes on disk so the GUI follows wallpaper theme switches automatically.
_COLORS_CSS_PROVIDER = None
# Wallust writes the live colour palette to the user dir, not the package dir.
_COLORS_CSS_PATH     = os.path.join(
    os.environ.get('VUTURELAND_USER_DIR',
                   os.path.join(os.environ.get('XDG_CONFIG_HOME',
                                               os.path.expanduser('~/.config')),
                                'vutureland')),
    'assets', 'colors_gtk.css',
)
# Fallback to the package's default palette if the user-dir copy doesn't exist
# yet (e.g. very first launch before welcome_to_vutureland.sh has run).
_COLORS_CSS_FALLBACK = os.path.join(
    os.environ.get('VUTURELAND_DIR',
                   os.path.realpath(os.path.join(os.path.dirname(__file__), '..'))),
    'assets', 'colors_gtk.css',
)

_PAGES = [
    ('home',          HomePage,          'go-home-symbolic',                          'Home'),
    ('hyprland',      HyprlandPage,      'preferences-desktop-display-symbolic',      'Hyprland'),
    ('waybar',        WaybarPage,        'view-grid-symbolic',                        'Bar'),
    ('wallpaper',     WallpaperPage,     'image-x-generic-symbolic',                  'Theme'),
    ('lockscreen',    LockscreenPage,    'system-lock-screen-symbolic',               'Power & Lock'),
    ('notifications', NotificationsPage, 'preferences-system-notifications-symbolic', 'Notifications'),
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


def _active_theme() -> str:
    """The active app design (set by the waybar picker). Defaults to 'miboro'."""
    base = os.environ.get('VUTURELAND_USER_DIR') or os.path.join(
        os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config')), 'vutureland')
    try:
        with open(os.path.join(base, 'active-theme')) as f:
            return f.read().strip() or 'miboro'
    except Exception:
        return 'miboro'


def reload_design_theme():
    """(Re)load gui/themes/<active>.css into the design provider so the panel
    restyles live after a design switch. No-op if the app isn't up yet."""
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

        # ── Monitor geometry (needed for size calculations) ───────────
        try:
            mon  = Gdk.Display.get_default().get_monitors().get_item(0)
            geom = mon.get_geometry()
            self._monitor_w, self._monitor_h = geom.width, geom.height
        except Exception:
            self._monitor_w, self._monitor_h = 1920, 1080

        # ── Theme override CSS provider (priority > main style.css) ───
        self._theme_provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), self._theme_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)

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
                    initial_value=self._settings.get('opacity_value', _OPACITY_DIM),
                )
                page.set_theme_callback(
                    self._apply_theme,
                    initial=self._settings.get('menu_theme', 'follow'),
                )
                w_pct = self._settings.get(
                    'panel_width_pct',
                    max(20, min(90, _PANEL_WIDTH * 100 // self._monitor_w)))
                page.set_size_callback(
                    self._apply_size,
                    w_pct=w_pct,
                    h_pct=self._settings.get('panel_height_pct', 100),
                )
                page.set_sidebar_labels_callback(
                    self._apply_sidebar_labels,
                    initial=self._settings.get('sidebar_labels', False),
                )
                page.set_logo_callback(
                    self._apply_logo,
                    initial=self._settings.get('logo_variant', 'full'),
                )
                page.set_placement_callback(
                    self._apply_placement,
                    side=self._settings.get('panel_side', 'left'),
                    valign=self._settings.get('panel_valign', 'bottom'),
                )
            if isinstance(page, NotificationsPage):
                page.set_values_callback(
                    self._apply_notifications,
                    margin_top_pct=self._settings.get('swaync_margin_top_pct', 10),
                    width_pct     =self._settings.get('swaync_width_pct',      23),
                )
            stack.add_named(page, name)
        stack.set_hexpand(True)
        stack.set_vexpand(True)

        # ── Content wrapper — only this part scrolls when the panel shrinks.
        # Banner and sidebar stay pinned. ScrolledWindow with
        # propagate-natural-* = false + min_content = 0 lets the wrapping
        # collapse below the Adw.PreferencesPage natural size.
        content_inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content_inner.add_css_class('content-area')
        content_inner.set_hexpand(True)
        content_inner.set_vexpand(True)
        content_inner.append(stack)

        content_wrap = Gtk.ScrolledWindow()
        content_wrap.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        content_wrap.set_propagate_natural_width(False)
        content_wrap.set_propagate_natural_height(False)
        content_wrap.set_min_content_width(0)
        content_wrap.set_min_content_height(0)
        content_wrap.set_hexpand(True)
        content_wrap.set_vexpand(True)
        content_wrap.set_child(content_inner)
        # Paint the panel background behind the scroll viewport too, so when the
        # panel is taller than its content the empty area below still shows the
        # panel colour (not the desktop) — otherwise a full-height panel looks
        # half-empty over a dark wallpaper.
        content_wrap.add_css_class('content-scroll')
        self._content_wrap = content_wrap

        # ── Left sidebar ──────────────────────────────────────────────
        self._sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._sidebar.add_css_class('nav-sidebar')
        self._sidebar.set_hexpand(False)   # stops img.hexpand from propagating up
        self._nav_icons:  list[Gtk.Image] = []
        self._nav_labels: list[Gtk.Label] = []

        nav_btns: list[Gtk.ToggleButton] = []

        for name, _, icon, tooltip in _PAGES:
            btn = self._make_nav_btn(name, icon, tooltip, stack, nav_btns)
            self._sidebar.append(btn)
            nav_btns.append(btn)

        # Spacer + separator push the settings button to the bottom
        spacer = Gtk.Box()
        spacer.set_vexpand(True)
        self._sidebar.append(spacer)
        sep = Gtk.Separator()
        sep.set_margin_top(4)
        sep.set_margin_bottom(4)
        self._sidebar.append(sep)

        for name, _, icon, tooltip in _BOTTOM_PAGES:
            btn = self._make_nav_btn(name, icon, tooltip, stack, nav_btns)
            self._sidebar.append(btn)
            nav_btns.append(btn)

        nav_btns[0].set_active(True)
        # Keep refs so the window can always reopen on the Home page (the daemon
        # only hides/shows, so the last-viewed page would otherwise persist).
        self._stack = stack
        self._nav_btns = nav_btns
        self._home_page = _PAGES[0][0]
        self._apply_sidebar_labels(self._settings.get('sidebar_labels', False),
                                   save=False)

        # ── Body ──────────────────────────────────────────────────────
        body = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        body.add_css_class('body-area')
        body.set_hexpand(True)
        body.set_vexpand(True)
        body.append(self._sidebar)
        body.append(content_wrap)
        self._body = body

        # ── Root: panel content (banner + body). Positioned bottom-left in
        # the fullscreen overlay; size driven directly by _apply_size().
        # The inner ScrolledWindow handles overflow so banner and sidebar
        # stay fixed when the user shrinks the panel.
        self._root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self._root.add_css_class('root-area')
        self._root.set_halign(Gtk.Align.START)
        self._root.set_valign(Gtk.Align.END)
        self._root.set_hexpand(False)
        self._root.set_vexpand(False)
        self._root.set_overflow(Gtk.Overflow.HIDDEN)
        self._root.append(self._build_banner())
        self._root.append(body)

        # Fullscreen transparent click-catcher; clicks on it close the panel.
        self._click_catcher = Gtk.Box()
        self._click_catcher.set_hexpand(True)
        self._click_catcher.set_vexpand(True)
        click_gesture = Gtk.GestureClick.new()
        click_gesture.set_button(0)   # any mouse button
        click_gesture.connect('pressed', self._on_outside_click)
        self._click_catcher.add_controller(click_gesture)

        overlay = Gtk.Overlay()
        overlay.set_child(self._click_catcher)
        overlay.add_overlay(self._root)
        self.set_child(overlay)

        # Apply saved size, opacity, and theme
        w_pct = self._settings.get(
            'panel_width_pct',
            max(20, min(90, _PANEL_WIDTH * 100 // self._monitor_w)))
        self._apply_size(w_pct, self._settings.get('panel_height_pct', 100),
                         save=False)
        self._apply_placement(self._settings.get('panel_side', 'left'),
                              self._settings.get('panel_valign', 'bottom'),
                              save=False)
        if self._settings.get('opacity_enabled', False):
            self._root.set_opacity(
                self._settings.get('opacity_value', _OPACITY_DIM))
        saved_theme = self._settings.get('menu_theme', 'follow')
        if saved_theme != 'follow':
            self._apply_theme(saved_theme, save=False)

        # Hide instead of destroy when closed — keeps the daemon alive
        self.connect('close-request', lambda w: w.hide() or True)

        # ── Escape key hides the panel ────────────────────────────────
        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect('key-pressed', self._on_key_pressed)
        self.add_controller(key_ctrl)

        # ── Watch wallust colors for changes ──────────────────────────
        self._setup_colors_watch()

    def _setup_colors_watch(self):
        if not os.path.exists(_COLORS_CSS_PATH):
            return
        try:
            gfile = Gio.File.new_for_path(_COLORS_CSS_PATH)
            self._colors_monitor = gfile.monitor_file(Gio.FileMonitorFlags.NONE, None)
            self._colors_monitor.connect('changed', self._on_colors_changed)
            self._colors_reload_id: int | None = None
        except Exception as e:
            print(f"[colors-watch] setup failed: {e}")

    def _on_colors_changed(self, _monitor, _file, _other, event_type):
        # Coalesce bursts of events (CHANGED + CHANGES_DONE_HINT + ATTRIBUTE_CHANGED)
        # into one reload after 150ms of silence.
        if self._colors_reload_id is not None:
            GLib.source_remove(self._colors_reload_id)
        self._colors_reload_id = GLib.timeout_add(150, self._reload_colors_css)

    def _reload_colors_css(self):
        self._colors_reload_id = None
        try:
            if _COLORS_CSS_PROVIDER is not None and os.path.exists(_COLORS_CSS_PATH):
                _COLORS_CSS_PROVIDER.load_from_path(_COLORS_CSS_PATH)
            if _BASE_CSS_PROVIDER is not None:
                _BASE_CSS_PROVIDER.load_from_path(_CSS)
        except Exception as e:
            print(f"[colors-watch] reload failed: {e}")
        return False  # don't repeat

    def _on_outside_click(self, _gesture, _n_press, _x, _y):
        # Fired only when the user clicks on the transparent area outside
        # the panel. Gtk.Overlay swallows clicks on the panel itself, so this
        # never triggers from within the panel content.
        self.hide()

    def slide_in(self):
        return False

    def reset_to_home(self):
        """Always show the Home page (called whenever the window is shown)."""
        stack = getattr(self, '_stack', None)
        if stack is not None:
            stack.set_visible_child_name(getattr(self, '_home_page', 'home'))
        for i, b in enumerate(getattr(self, '_nav_btns', [])):
            b.set_active(i == 0)

    def close_animated(self):
        self.hide()

    def _make_nav_btn(self, name: str, icon: str, tooltip: str,
                      stack: Adw.ViewStack, nav_btns: list) -> Gtk.ToggleButton:
        btn = Gtk.ToggleButton()
        btn.add_css_class('nav-btn')
        btn.set_tooltip_text(tooltip)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        img = Gtk.Image.new_from_icon_name(icon)
        img.set_halign(Gtk.Align.CENTER)
        img.set_hexpand(True)            # centres the icon when label is hidden
        box.append(img)
        lbl = Gtk.Label(label=tooltip)
        lbl.set_xalign(0.0)
        lbl.set_hexpand(False)
        lbl.set_visible(False)
        box.append(lbl)
        btn.set_child(box)
        self._nav_icons.append(img)
        self._nav_labels.append(lbl)

        btn.connect('toggled', self._on_nav_toggled, name, stack, nav_btns)
        return btn

    def _apply_sidebar_labels(self, show: bool, save: bool = True):
        for img, lbl in zip(self._nav_icons, self._nav_labels):
            lbl.set_visible(show)
            if show:
                img.set_halign(Gtk.Align.START)
                img.set_hexpand(False)
                img.set_margin_start(8)
                lbl.set_hexpand(True)
            else:
                img.set_halign(Gtk.Align.CENTER)
                img.set_hexpand(True)
                img.set_margin_start(0)
                lbl.set_hexpand(False)
        self._sidebar.set_size_request(160 if show else 56, -1)
        if save:
            self._settings['sidebar_labels'] = show
            _save_settings(self._settings)

    def _apply_notifications(self, margin_top_pct: int, width_pct: int):
        self._settings['swaync_margin_top_pct'] = margin_top_pct
        self._settings['swaync_width_pct']      = width_pct
        _save_settings(self._settings)

    def _apply_opacity(self, value: float):
        self._root.set_opacity(value)
        self._settings['opacity_enabled'] = value < 1.0
        self._settings['opacity_value']   = value
        _save_settings(self._settings)

    def _apply_theme(self, theme: str, save: bool = True):
        css = _THEME_CSS.get(theme, '')
        self._theme_provider.load_from_string(css)
        # Re-parse the base style.css so its @color refs resolve to the new
        # @define-color overrides — without this, only widgets created after
        # the theme change would use the new colours.
        if _BASE_CSS_PROVIDER is not None:
            try:
                _BASE_CSS_PROVIDER.load_from_path(_CSS)
            except Exception as e:
                print(f"[theme] base reload: {e}")
        # Let Adwaita handle its own light/dark text colours
        style_mgr = Adw.StyleManager.get_default()
        if theme == 'bright':
            style_mgr.set_color_scheme(Adw.ColorScheme.FORCE_LIGHT)
        elif theme == 'dark':
            style_mgr.set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        else:
            style_mgr.set_color_scheme(Adw.ColorScheme.DEFAULT)
        if save:
            self._settings['menu_theme'] = theme
            _save_settings(self._settings)

    _PLACE_CLASSES = [
        'place-left-top', 'place-left-center', 'place-left-bottom',
        'place-right-top', 'place-right-center', 'place-right-bottom',
    ]

    def _apply_placement(self, side: str, valign: str, save: bool = True):
        """Move the panel to one of six spots: {left,right} × {top,center,bottom}.
        The window itself stays a fullscreen layer surface; only the inner panel
        (`_root`) is re-aligned, its interior-facing border/rounding swapped, and
        the nav sidebar mirrored to sit against the screen edge."""
        side   = side if side in ('left', 'right') else 'left'
        valign = valign if valign in ('top', 'center', 'bottom') else 'bottom'

        self._root.set_halign(Gtk.Align.START if side == 'left' else Gtk.Align.END)
        self._root.set_valign({'top': Gtk.Align.START,
                               'center': Gtk.Align.CENTER,
                               'bottom': Gtk.Align.END}[valign])

        for cls in self._PLACE_CLASSES:
            self._root.remove_css_class(cls)
        self._root.add_css_class(f'place-{side}-{valign}')

        # Mirror the nav sidebar so it stays against the anchored screen edge:
        # left placement → sidebar first (left), right placement → sidebar last.
        if side == 'left':
            self._body.reorder_child_after(self._sidebar, None)
        else:
            self._body.reorder_child_after(self._sidebar, self._content_wrap)

        if save:
            self._settings['panel_side']   = side
            self._settings['panel_valign'] = valign
            _save_settings(self._settings)

    def _apply_size(self, w_pct: int, h_pct: int, save: bool = True):
        w = int(self._monitor_w * w_pct / 100)
        h = int(self._monitor_h * h_pct / 100)
        # The root is overflow=HIDDEN, so whatever we put as size_request is
        # the visible panel size. Banner and sidebar are above/beside the
        # inner ScrolledWindow, which absorbs the height change.
        self._root.set_size_request(w, h)
        self._root.queue_resize()
        if save:
            self._settings['panel_width_pct']  = w_pct
            self._settings['panel_height_pct'] = h_pct
            _save_settings(self._settings)

    def _on_key_pressed(self, ctrl, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.close_animated()
            return True
        return False

    def _build_banner(self):
        self._banner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self._banner.add_css_class('logo-bar')
        self._banner.set_hexpand(True)
        self._banner.set_vexpand(False)
        self._render_banner(self._settings.get('logo_variant', 'full'))
        return self._banner

    def _render_banner(self, variant: str):
        # Strip existing child
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
        # Only pin the height; let the width scale down (SCALE_DOWN) so the logo
        # doesn't force a wide minimum on the whole panel.
        pic.set_can_shrink(True)
        pic.set_size_request(-1, pb.get_height())
        self._banner.append(pic)

    def _apply_logo(self, variant: str, save: bool = True):
        self._render_banner(variant)
        if save:
            self._settings['logo_variant'] = variant
            _save_settings(self._settings)

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
        self.hold()   # keep process alive when window is hidden
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
        global _BASE_CSS_PROVIDER, _COLORS_CSS_PROVIDER, _DESIGN_CSS_PROVIDER
        display = Gdk.Display.get_default()

        # Force a complete icon theme for our symbolic icons. The user's system
        # icon theme (e.g. Papirus-Dark, set via gsettings) may be missing many
        # freedesktop symbolic names, which would render every icon as the broken
        # "image-missing" placeholder. Adwaita ships with GTK and has them all.
        Gtk.Settings.get_default().set_property('gtk-icon-theme-name', 'Adwaita')

        # Wallust colors — loaded first so style.css can resolve @bg-primary etc.
        _COLORS_CSS_PROVIDER = Gtk.CssProvider()
        if os.path.exists(_COLORS_CSS_PATH):
            _COLORS_CSS_PROVIDER.load_from_path(_COLORS_CSS_PATH)
        elif os.path.exists(_COLORS_CSS_FALLBACK):
            _COLORS_CSS_PROVIDER.load_from_path(_COLORS_CSS_FALLBACK)
        Gtk.StyleContext.add_provider_for_display(
            display, _COLORS_CSS_PROVIDER,
            Gtk.STYLE_PROVIDER_PRIORITY_USER)

        _BASE_CSS_PROVIDER = Gtk.CssProvider()
        _BASE_CSS_PROVIDER.load_from_path(_CSS)
        Gtk.StyleContext.add_provider_for_display(
            display, _BASE_CSS_PROVIDER,
            Gtk.STYLE_PROVIDER_PRIORITY_USER)

        # Active design's GUI theme overrides (gui/themes/<active>.css), loaded
        # after the base so it wins. Missing file = no-op (base IS miboro).
        # Kept in a global provider so a design switch can restyle it live.
        _DESIGN_CSS_PROVIDER = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            display, _DESIGN_CSS_PROVIDER, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        reload_design_theme()

        win = MainWindow(application=self)

        # ── Layer shell setup (must happen before present()) ──────────
        Gtk4LayerShell.init_for_window(win)
        Gtk4LayerShell.set_namespace(win, 'vutureland-settings')
        # OVERLAY (above the TOP layer where waybar lives) so the panel is always
        # the topmost layer — it shows over waybar even when one is in the way.
        Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.OVERLAY)
        # Fullscreen layer so we can detect clicks outside the panel.
        # The actual panel content is positioned bottom-left inside an overlay.
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.LEFT,   True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.RIGHT,  True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.TOP,    True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.BOTTOM, True)
        Gtk4LayerShell.set_exclusive_zone(win, -1)
        Gtk4LayerShell.set_keyboard_mode(win, Gtk4LayerShell.KeyboardMode.ON_DEMAND)

        # SIGUSR1: toggle window visibility (sent by --toggle). Reset to the Home
        # page whenever the window becomes visible.
        def _toggle():
            show = not win.get_visible()
            if show:
                win.reset_to_home()
            win.set_visible(show)
            return GLib.SOURCE_CONTINUE
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, _toggle)

        # SIGTERM: actually quit the process
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM,
                             lambda: (self.quit(), GLib.SOURCE_REMOVE)[1])

        win.present()
        if os.environ.get('VUTURELAND_START_HIDDEN') == '1':
            win.hide()
        else:
            GLib.idle_add(win.slide_in)


if __name__ == '__main__':
    VuturelandSettings().run()
