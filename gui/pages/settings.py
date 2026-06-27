from __future__ import annotations
import gi, os, signal, subprocess, threading
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib


# ── Daemon helpers ────────────────────────────────────────────────────────────

def _vtl() -> str:
    return os.environ.get('VUTURELAND_DIR') or os.path.realpath(
        os.path.join(os.path.dirname(__file__), '../..'))


def _stop_notify() -> None:
    try:
        pid = int(open('/tmp/vutureland-notify.pid').read().strip())
        os.kill(pid, signal.SIGTERM)
    except Exception:
        pass


def _start_notify() -> None:
    gui = os.path.join(_vtl(), 'gui', 'main.py')
    threading.Thread(
        target=lambda: subprocess.run(
            ['python3', gui, '--notify', '--daemon'], capture_output=True),
        daemon=True,
    ).start()


def _stop_osd() -> None:
    runtime = os.environ.get('XDG_RUNTIME_DIR', '/tmp')
    fifo = os.path.join(runtime, 'vutureland-osd.fifo')
    try:
        subprocess.run(['fuser', '-TERM', '-k', fifo], capture_output=True)
    except Exception:
        pass


def _start_osd() -> None:
    script = os.path.join(_vtl(), 'assets', 'scripts', 'launch-osd.sh')
    threading.Thread(
        target=lambda: subprocess.run(['bash', script], capture_output=True),
        daemon=True,
    ).start()


class SettingsPage(Adw.PreferencesPage):
    _THEMES = [
        ('follow', 'Follow Theme'),
        ('dark',   'Dark'),
        ('bright', 'Bright'),
    ]
    _LOGOS = [
        ('full',   'Full'),
        ('simple', 'Simple'),
        ('none',   'None'),
    ]
    _SIDES = [
        ('left',  'Left'),
        ('right', 'Right'),
    ]
    _VPOS = [
        ('top',    'Top'),
        ('center', 'Center'),
        ('bottom', 'Bottom'),
    ]

    def __init__(self):
        super().__init__()
        self._opacity_cb          = None
        self._theme_cb            = None
        self._size_cb             = None
        self._sidebar_labels_cb   = None
        self._sidebar_autohide_cb = None
        self._logo_cb             = None
        self._placement_cb        = None
        self._lm_cb               = None
        self._shell_cb            = None
        self._lm_updating         = False
        self._size_apply_id       = None
        self._build_ui()

    # ── External init ────────────────────────────────────────────────────────

    def set_sidebar_labels_callback(self, cb, initial: bool = False):
        self._sidebar_labels_switch.set_active(initial)
        self._sidebar_labels_cb = cb

    def set_sidebar_autohide_callback(self, cb, initial: bool = False):
        self._sidebar_autohide_switch.set_active(initial)
        self._sidebar_autohide_cb = cb

    def set_opacity_callback(self, cb, initial: bool = False,
                             initial_value: float = 0.88):
        self._opacity_switch.set_active(initial)
        self._opacity_scale.set_value(initial_value)
        self._opacity_slider_row.set_visible(initial)
        self._opacity_cb = cb

    def set_theme_callback(self, cb, initial: str = 'follow'):
        idx = next((i for i, (k, _) in enumerate(self._THEMES) if k == initial), 0)
        self._theme_combo.set_selected(idx)
        self._theme_cb = cb

    def set_logo_callback(self, cb, initial: str = 'full'):
        idx = next((i for i, (k, _) in enumerate(self._LOGOS) if k == initial), 0)
        self._logo_combo.set_selected(idx)
        self._logo_cb = cb

    def set_size_callback(self, cb, w_pct: int = 50, h_pct: int = 100):
        self._width_scale.set_value(w_pct)
        self._height_scale.set_value(h_pct)
        self._size_cb = cb

    def set_placement_callback(self, cb, side: str = 'left', valign: str = 'bottom'):
        s_idx = next((i for i, (k, _) in enumerate(self._SIDES) if k == side), 0)
        v_idx = next((i for i, (k, _) in enumerate(self._VPOS) if k == valign), 2)
        self._side_combo.set_selected(s_idx)
        self._vpos_combo.set_selected(v_idx)
        self._placement_cb = cb

    def set_low_memory_callback(self, cb, initial: bool = False):
        self._lm_updating = True
        self._lm_switch.set_active(initial)
        self._lm_updating = False
        self._lm_cb = cb

    def set_shell_backend_callback(self, cb, initial: str = 'waybar'):
        self._shell_switch.set_active(initial == 'quickshell')
        self._shell_cb = cb

    # ── Build ────────────────────────────────────────────────────────────────

    def _build_ui(self):
        # Appearance
        appearance = Adw.PreferencesGroup(title='Appearance')

        self._theme_combo = Adw.ComboRow(
            title='Menu Theme',
            subtitle='Choose how the settings panel is coloured',
            model=Gtk.StringList.new([label for _, label in self._THEMES]),
        )
        self._theme_combo.connect('notify::selected', self._on_theme_combo_changed)
        appearance.add(self._theme_combo)

        self._logo_combo = Adw.ComboRow(
            title='Header Logo',
            subtitle='Which logo to display at the top of the panel',
            model=Gtk.StringList.new([label for _, label in self._LOGOS]),
        )
        self._logo_combo.connect('notify::selected', self._on_logo_combo_changed)
        appearance.add(self._logo_combo)
        self.add(appearance)

        # Sidebar
        sidebar = Adw.PreferencesGroup(title='Sidebar')

        labels_row = Adw.ActionRow(
            title='Show labels',
            subtitle='Display the page name next to each sidebar icon',
        )
        self._sidebar_labels_switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        self._sidebar_labels_switch.connect('notify::active',
                                            self._on_sidebar_labels_toggled)
        labels_row.add_suffix(self._sidebar_labels_switch)
        labels_row.set_activatable_widget(self._sidebar_labels_switch)
        sidebar.add(labels_row)

        autohide_row = Adw.ActionRow(
            title='Auto-hide sidebar',
            subtitle='Sidebar appears when you hover near the left edge',
        )
        self._sidebar_autohide_switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        self._sidebar_autohide_switch.connect('notify::active',
                                              self._on_sidebar_autohide_toggled)
        autohide_row.add_suffix(self._sidebar_autohide_switch)
        autohide_row.set_activatable_widget(self._sidebar_autohide_switch)
        sidebar.add(autohide_row)
        self.add(sidebar)

        # Transparency
        transparency = Adw.PreferencesGroup(title='Transparency')

        sw_row = Adw.ActionRow(
            title='Enable transparency',
            subtitle='Show the blurred desktop through the panel',
        )
        self._opacity_switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        self._opacity_switch.connect('notify::active', self._on_opacity_switch)
        sw_row.add_suffix(self._opacity_switch)
        sw_row.set_activatable_widget(self._opacity_switch)
        transparency.add(sw_row)

        # Opacity slider as its own row (hidden until switch is on)
        self._opacity_slider_row = Adw.ActionRow(title='Opacity')
        self._opacity_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, 0.30, 0.99, 0.01)
        self._opacity_scale.set_size_request(220, -1)
        self._opacity_scale.set_draw_value(True)
        self._opacity_scale.set_value_pos(Gtk.PositionType.RIGHT)
        self._opacity_scale.set_value(0.88)
        self._opacity_scale.set_valign(Gtk.Align.CENTER)
        self._opacity_scale.set_hexpand(True)
        self._opacity_scale.connect('value-changed', self._on_opacity_scale)
        self._opacity_slider_row.add_suffix(self._opacity_scale)
        self._opacity_slider_row.set_visible(False)
        transparency.add(self._opacity_slider_row)
        self.add(transparency)

        # Placement
        placement = Adw.PreferencesGroup(
            title='Placement',
            description='Which screen edge the panel attaches to, and where along it.')
        self._side_combo = Adw.ComboRow(
            title='Side',
            model=Gtk.StringList.new([label for _, label in self._SIDES]),
        )
        self._side_combo.connect('notify::selected', self._on_placement_changed)
        placement.add(self._side_combo)
        self._vpos_combo = Adw.ComboRow(
            title='Vertical position',
            model=Gtk.StringList.new([label for _, label in self._VPOS]),
        )
        self._vpos_combo.connect('notify::selected', self._on_placement_changed)
        placement.add(self._vpos_combo)
        self.add(placement)

        # Panel Size
        panel = Adw.PreferencesGroup(title='Panel Size')

        self._width_scale  = self._add_slider_row(panel, 'Width (%)',  20, 90,  50)
        self._height_scale = self._add_slider_row(panel, 'Height (%)', 40, 100, 100)
        self.add(panel)

        # Bar backend
        bar = Adw.PreferencesGroup(title='Bar')

        shell_row = Adw.ActionRow(
            title='Use Quickshell Bar',
            subtitle='Replace Waybar with the Quickshell bar — takes effect immediately',
        )
        self._shell_switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        self._shell_switch.connect('notify::active', self._on_shell_backend_toggled)
        shell_row.add_suffix(self._shell_switch)
        shell_row.set_activatable_widget(self._shell_switch)
        bar.add(shell_row)
        self.add(bar)

        # Performance
        perf = Adw.PreferencesGroup(title='Performance')

        lm_row = Adw.ActionRow(
            title='Low Memory Mode',
            subtitle='Stops the OSD and notification daemons — '
                     'volume/brightness overlays and desktop notifications '
                     'will not appear until this is disabled.',
        )
        self._lm_switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        self._lm_switch.connect('notify::active', self._on_low_memory_toggled)
        lm_row.add_suffix(self._lm_switch)
        lm_row.set_activatable_widget(self._lm_switch)
        perf.add(lm_row)
        self.add(perf)

    def _add_slider_row(self, group, title, lo, hi, default) -> Gtk.Scale:
        row = Adw.ActionRow(title=title)
        sc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, lo, hi, 1)
        sc.set_size_request(220, -1)
        sc.set_draw_value(True)
        sc.set_value_pos(Gtk.PositionType.RIGHT)
        sc.set_value(default)
        sc.set_valign(Gtk.Align.CENTER)
        sc.set_hexpand(True)
        sc.connect('value-changed', self._on_size_changed)
        row.add_suffix(sc)
        group.add(row)
        return sc

    # ── Handlers ─────────────────────────────────────────────────────────────

    def _on_theme_combo_changed(self, combo, _):
        idx = combo.get_selected()
        if 0 <= idx < len(self._THEMES) and self._theme_cb:
            self._theme_cb(self._THEMES[idx][0])

    def _on_logo_combo_changed(self, combo, _):
        idx = combo.get_selected()
        if 0 <= idx < len(self._LOGOS) and self._logo_cb:
            self._logo_cb(self._LOGOS[idx][0])

    def _on_sidebar_labels_toggled(self, switch: Gtk.Switch, _):
        if self._sidebar_labels_cb:
            self._sidebar_labels_cb(switch.get_active())

    def _on_sidebar_autohide_toggled(self, switch: Gtk.Switch, _):
        if self._sidebar_autohide_cb:
            self._sidebar_autohide_cb(switch.get_active())

    def _on_opacity_switch(self, switch: Gtk.Switch, _):
        active = switch.get_active()
        self._opacity_slider_row.set_visible(active)
        if self._opacity_cb:
            self._opacity_cb(self._opacity_scale.get_value() if active else 1.0)

    def _on_opacity_scale(self, scale: Gtk.Scale):
        if self._opacity_switch.get_active() and self._opacity_cb:
            self._opacity_cb(scale.get_value())

    def _on_placement_changed(self, _combo, _):
        s_idx = self._side_combo.get_selected()
        v_idx = self._vpos_combo.get_selected()
        if 0 <= s_idx < len(self._SIDES) and 0 <= v_idx < len(self._VPOS) \
                and self._placement_cb:
            self._placement_cb(self._SIDES[s_idx][0], self._VPOS[v_idx][0])

    def _on_size_changed(self, _):
        # Debounce — only apply 250 ms after the user stops moving the slider,
        # so the panel doesn't relayout on every intermediate value.
        if self._size_apply_id is not None:
            GLib.source_remove(self._size_apply_id)
        self._size_apply_id = GLib.timeout_add(250, self._fire_size_cb)

    def _fire_size_cb(self):
        self._size_apply_id = None
        if self._size_cb:
            self._size_cb(int(self._width_scale.get_value()),
                          int(self._height_scale.get_value()))
        return False

    def _on_low_memory_toggled(self, switch: Gtk.Switch, _):
        if self._lm_updating:
            return
        if switch.get_active():
            self._show_low_memory_dialog(switch)
        else:
            self._apply_low_memory(False)

    def _on_shell_backend_toggled(self, switch: Gtk.Switch, _):
        if self._shell_cb:
            self._shell_cb('quickshell' if switch.get_active() else 'waybar')

    def _show_low_memory_dialog(self, switch: Gtk.Switch):
        dialog = Adw.AlertDialog(
            heading='Enable Low Memory Mode?',
            body='The OSD daemon and notification daemon will be stopped immediately.\n\n'
                 'Volume/brightness overlays and desktop notifications will not work '
                 'until Low Memory Mode is turned off again.',
        )
        dialog.add_response('cancel',  'Cancel')
        dialog.add_response('confirm', 'Enable')
        dialog.set_response_appearance('confirm', Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_close_response('cancel')
        dialog.connect('response', lambda d, r: self._on_lm_dialog_response(r, switch))
        dialog.present(self.get_root())

    def _on_lm_dialog_response(self, response: str, switch: Gtk.Switch):
        if response == 'confirm':
            self._apply_low_memory(True)
        else:
            self._lm_updating = True
            switch.set_active(False)
            self._lm_updating = False

    def _apply_low_memory(self, enabled: bool):
        if enabled:
            _stop_osd()
            _stop_notify()
        else:
            _start_osd()
            _start_notify()
        if self._lm_cb:
            self._lm_cb(enabled)
