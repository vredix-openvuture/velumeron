from __future__ import annotations
import gi, os, subprocess, threading, signal as _signal
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib
import osd_config
import notify_config


def _vtl() -> str:
    return os.environ.get('VUTURELAND_DIR') or os.path.realpath(
        os.path.join(os.path.dirname(__file__), '../..'))


def _restart_osd() -> None:
    script = os.path.join(_vtl(), 'assets', 'scripts', 'launch-osd.sh')
    threading.Thread(
        target=lambda: subprocess.run(['bash', script], capture_output=True),
        daemon=True,
    ).start()


def _restart_notify() -> None:
    try:
        pid = int(open('/tmp/vutureland-notify.pid').read().strip())
        os.kill(pid, _signal.SIGTERM)
    except Exception:
        pass
    gui = os.path.join(_vtl(), 'gui', 'main.py')
    threading.Thread(
        target=lambda: subprocess.run(
            ['python3', gui, '--notify', '--daemon'], capture_output=True),
        daemon=True,
    ).start()


# ── Generic row helpers ───────────────────────────────────────────────────────

def _toggle_row(group, title, subtitle, cfg, key, save_fn):
    row = Adw.ActionRow(title=title, subtitle=subtitle)
    sw  = Gtk.Switch()
    sw.set_valign(Gtk.Align.CENTER)
    sw.set_active(bool(cfg.get(key, True)))
    sw.connect('notify::active', lambda s, _: save_fn({key: s.get_active()}))
    row.add_suffix(sw)
    row.set_activatable_widget(sw)
    group.add(row)
    return sw


def _combo_row(group, title, subtitle, options: list[tuple[str, str]], cfg, key, save_fn):
    keys   = [k for k, _ in options]
    labels = [lbl for _, lbl in options]
    current = cfg.get(key, keys[0])
    idx = keys.index(current) if current in keys else 0
    row = Adw.ComboRow(title=title, subtitle=subtitle)
    row.set_model(Gtk.StringList.new(labels))
    row.set_selected(idx)
    row.connect('notify::selected',
                lambda r, _: save_fn({key: keys[r.get_selected()]}))
    group.add(row)
    return row


def _spin_row(group, title, subtitle, value, lo, hi, step, digits, on_change):
    adj  = Gtk.Adjustment(value=value, lower=lo, upper=hi, step_increment=step)
    spin = Gtk.SpinButton(adjustment=adj, digits=digits)
    spin.set_valign(Gtk.Align.CENTER)
    spin.connect('value-changed', lambda w: on_change(w.get_value()))
    row = Adw.ActionRow(title=title, subtitle=subtitle)
    row.add_suffix(spin)
    row.set_activatable_widget(spin)
    group.add(row)
    return spin


# ── Position grid (shared by both OSD types) ─────────────────────────────────

_POSITIONS = [
    ('top-left',      0, 0, 'Top-left'),
    ('top-center',    0, 1, 'Top-center'),
    ('top-right',     0, 2, 'Top-right'),
    ('center-left',   1, 0, 'Center-left  (vertical / side)'),
    (None,            1, 1, ''),
    ('center-right',  1, 2, 'Center-right  (vertical / side)'),
    ('bottom-left',   2, 0, 'Bottom-left'),
    ('bottom-center', 2, 1, 'Bottom-center'),
    ('bottom-right',  2, 2, 'Bottom-right'),
]

_POS_SYMBOL = {
    'top-left':      '↖', 'top-center':    '↑', 'top-right':     '↗',
    'center-left':   '↕←',                       'center-right':  '→↕',
    'bottom-left':   '↙', 'bottom-center': '↓', 'bottom-right':  '↘',
}


def _build_position_group(
    cfg,
    pos_key:    str,
    style_key:  str,
    save_fn,
    restart_fn,
    title:      str = 'Position',
    description: str = 'Changes take effect after restarting.',
    restart_label: str = 'Restart OSD Daemon',
) -> Adw.PreferencesGroup:
    group = Adw.PreferencesGroup(title=title, description=description)

    current = cfg.get(pos_key, 'bottom-center')
    grid = Gtk.Grid()
    grid.set_row_spacing(4)
    grid.set_column_spacing(4)
    grid.set_halign(Gtk.Align.CENTER)
    grid.set_margin_top(10)
    grid.set_margin_bottom(6)

    first_btn: Gtk.ToggleButton | None = None
    for pos, row, col, tooltip in _POSITIONS:
        if pos is None:
            spacer = Gtk.Label(label='')
            spacer.set_size_request(72, 36)
            grid.attach(spacer, col, row, 1, 1)
            continue
        btn = Gtk.ToggleButton(label=_POS_SYMBOL.get(pos, pos))
        btn.set_size_request(72, 36)
        btn.set_tooltip_text(tooltip)
        if first_btn is None:
            first_btn = btn
        else:
            btn.set_group(first_btn)
        if pos == current:
            btn.set_active(True)

        def _on_toggled(b, p=pos):
            if b.get_active():
                save_fn({pos_key: p})

        btn.connect('toggled', _on_toggled)
        grid.attach(btn, col, row, 1, 1)

    grid_row = Adw.PreferencesRow()
    grid_row.set_activatable(False)
    grid_row.set_child(grid)
    group.add(grid_row)

    _combo_row(group, 'Style',
               'Float: inset from the edge — Dock: flush against the screen edge',
               [('float', 'Float'), ('dock', 'Dock')],
               cfg, style_key, save_fn)

    restart_btn = Gtk.Button(label=restart_label)
    restart_btn.add_css_class('pill')
    restart_btn.set_halign(Gtk.Align.CENTER)
    restart_btn.set_margin_top(4)
    restart_btn.set_margin_bottom(6)
    restart_btn.connect('clicked', lambda _: restart_fn())
    restart_row = Adw.PreferencesRow()
    restart_row.set_activatable(False)
    restart_row.set_child(restart_btn)
    group.add(restart_row)

    return group


# ── OSD Page ──────────────────────────────────────────────────────────────────

class OsdPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__()
        self._sys_groups:    list[Adw.PreferencesGroup] = []
        self._notify_groups: list[Adw.PreferencesGroup] = []
        self._build()

    def _build(self) -> None:
        # ── Selector ──────────────────────────────────────────────────────────
        selector_group = Adw.PreferencesGroup()
        btn_sys   = Gtk.ToggleButton(label='System OSD')
        btn_notif = Gtk.ToggleButton(label='Notification OSD')
        btn_notif.set_group(btn_sys)
        btn_sys.set_active(True)

        seg_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        seg_box.add_css_class('linked')
        seg_box.set_halign(Gtk.Align.CENTER)
        seg_box.set_margin_top(6)
        seg_box.set_margin_bottom(6)
        seg_box.append(btn_sys)
        seg_box.append(btn_notif)

        sel_row = Adw.PreferencesRow()
        sel_row.set_activatable(False)
        sel_row.set_child(seg_box)
        selector_group.add(sel_row)
        self.add(selector_group)

        # ── System OSD groups ─────────────────────────────────────────────────
        cfg = osd_config.load()

        pos_grp = _build_position_group(
            cfg,
            pos_key       = 'osd_position',
            style_key     = 'osd_style',
            save_fn       = osd_config.save,
            restart_fn    = _restart_osd,
            title         = 'Position',
            description   = 'Where the OSD appears. Center-left / Center-right use a '
                            'vertical layout (bar fills upward). Changes take effect after restart.',
            restart_label = 'Restart OSD Daemon',
        )
        self._sys_groups.append(pos_grp)
        self.add(pos_grp)

        vol = Adw.PreferencesGroup(title='Volume OSD')
        _toggle_row(vol, 'Enable', 'Show OSD when volume changes',
                    cfg, 'osd_volume', osd_config.save)
        _combo_row(vol, 'Display mode', 'What to show on the banner', [
            ('bar_and_value', 'Bar + value'),
            ('bar_only',      'Bar only'),
            ('value_only',    'Value only'),
        ], cfg, 'volume_display', osd_config.save)
        _toggle_row(vol, 'Show device name',
                    'Display the active audio output device below the bar',
                    cfg, 'show_device', osd_config.save)
        self._sys_groups.append(vol)
        self.add(vol)

        bri = Adw.PreferencesGroup(title='Brightness OSD')
        _toggle_row(bri, 'Enable', 'Show OSD when brightness changes',
                    cfg, 'osd_brightness', osd_config.save)
        _combo_row(bri, 'Display mode', 'What to show on the banner', [
            ('bar_and_value', 'Bar + value'),
            ('bar_only',      'Bar only'),
            ('value_only',    'Value only'),
        ], cfg, 'brightness_display', osd_config.save)
        self._sys_groups.append(bri)
        self.add(bri)

        ws = Adw.PreferencesGroup(title='Workspace OSD')
        _toggle_row(ws, 'Enable', 'Show OSD when switching workspaces',
                    cfg, 'osd_workspace', osd_config.save)
        _toggle_row(ws, 'Same monitor only',
                    'Only trigger when the workspace changes on the active monitor',
                    cfg, 'osd_workspace_local_only', osd_config.save)
        _combo_row(ws, 'Display mode', 'What to show on the banner', [
            ('dots_only',       'Dots only'),
            ('number_only',     'Number only'),
            ('dots_and_number', 'Dots + number'),
        ], cfg, 'workspace_display', osd_config.save)
        self._sys_groups.append(ws)
        self.add(ws)

        app_grp = Adw.PreferencesGroup(
            title='Appearance',
            description='Size and timing of the banner. Changes apply the next time the OSD appears.')
        _spin_row(app_grp, 'Display duration', 'How long the banner stays visible (seconds)',
                  cfg['duration_ms'] / 1000.0, 0.5, 6.0, 0.1, 1,
                  lambda v: osd_config.save({'duration_ms': int(round(v * 1000))}))
        _spin_row(app_grp, 'Edge margin', 'Gap from the screen edge (px)',
                  cfg['margin_px'], 0, 600, 10, 0,
                  lambda v: osd_config.save({'margin_px': int(v)}))
        _spin_row(app_grp, 'Width', 'Banner width for horizontal positions (px)',
                  cfg['width_px'], 100, 900, 10, 0,
                  lambda v: osd_config.save({'width_px': int(v)}))
        _spin_row(app_grp, 'Height', 'Banner height for horizontal positions (px)',
                  cfg['height_px'], 24, 200, 4, 0,
                  lambda v: osd_config.save({'height_px': int(v)}))
        self._sys_groups.append(app_grp)
        self.add(app_grp)

        # ── Notification OSD groups (hidden by default) ───────────────────────
        ncfg = notify_config.load()

        npos_grp = _build_position_group(
            ncfg,
            pos_key       = 'notify_position',
            style_key     = 'notify_style',
            save_fn       = notify_config.save,
            restart_fn    = _restart_notify,
            title         = 'Position',
            description   = 'Where notification popups appear on screen. '
                            'Changes take effect after restarting the daemon.',
            restart_label = 'Restart Notification Daemon',
        )
        npos_grp.set_visible(False)
        self._notify_groups.append(npos_grp)
        self.add(npos_grp)

        napp = Adw.PreferencesGroup(
            title='Appearance',
            description='Card size and stacking. Changes apply to the next popup.')
        _spin_row(napp, 'Card width', 'Width of each notification card (px)',
                  ncfg['notify_width_px'], 240, 640, 10, 0,
                  lambda v: notify_config.save({'notify_width_px': int(v)}))
        _spin_row(napp, 'Edge margin', 'Gap from the screen edge in Float style (px)',
                  ncfg['notify_margin_px'], 0, 200, 4, 0,
                  lambda v: notify_config.save({'notify_margin_px': int(v)}))
        _spin_row(napp, 'Card overlap', 'How many pixels each card overlaps the one behind it',
                  ncfg['notify_overlap_px'], 0, 24, 1, 0,
                  lambda v: notify_config.save({'notify_overlap_px': int(v)}))
        _spin_row(napp, 'Max popups', 'Maximum cards on screen at once (oldest is dropped)',
                  ncfg['notify_max_popups'], 1, 10, 1, 0,
                  lambda v: notify_config.save({'notify_max_popups': int(v)}))
        _combo_row(napp, 'Stack order',
                   'Which end new notifications appear at',
                   [('newest_top', 'Newest on top'), ('newest_bottom', 'Newest on bottom')],
                   ncfg, 'notify_stack_order', notify_config.save)
        napp.set_visible(False)
        self._notify_groups.append(napp)
        self.add(napp)

        nbeh = Adw.PreferencesGroup(
            title='Behavior',
            description='Timing, content, and click interaction for notification popups.')
        _spin_row(nbeh, 'Default timeout',
                  'Auto-dismiss after this many seconds (0 = never)',
                  ncfg['notify_timeout_ms'] / 1000.0, 0.0, 30.0, 0.5, 1,
                  lambda v: notify_config.save({'notify_timeout_ms': int(round(v * 1000))}))
        _spin_row(nbeh, 'Heading size', 'Font size of the notification title line (px); restart daemon to apply',
                  ncfg['notify_heading_size_px'], 8, 28, 1, 0,
                  lambda v: notify_config.save({'notify_heading_size_px': int(v)}))
        _toggle_row(nbeh, 'Show icons', 'Display the app/image icon on the card',
                    ncfg, 'notify_show_icons', notify_config.save)
        _toggle_row(nbeh, 'Show app name', 'Show the sending application name in the header',
                    ncfg, 'notify_show_app_name', notify_config.save)
        _combo_row(nbeh, 'Click action',
                   'What happens when you click on a notification popup',
                   [
                       ('dismiss', 'Dismiss'),
                       ('action',  'Invoke default action'),
                       ('none',    'Do nothing'),
                   ],
                   ncfg, 'notify_click_action', notify_config.save)
        nbeh.set_visible(False)
        self._notify_groups.append(nbeh)
        self.add(nbeh)

        # Wire the selector buttons after groups are registered
        btn_notif.connect('toggled', lambda b: self._switch_view(b.get_active()))

    def _switch_view(self, show_notify: bool) -> None:
        for g in self._sys_groups:
            g.set_visible(not show_notify)
        for g in self._notify_groups:
            g.set_visible(show_notify)
