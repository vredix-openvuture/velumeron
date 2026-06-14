from __future__ import annotations
import gi, os, subprocess, threading
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib
import osd_config


def _vtl() -> str:
    return os.environ.get('VUTURELAND_DIR') or os.path.realpath(
        os.path.join(os.path.dirname(__file__), '../..'))


def _restart_osd():
    script = os.path.join(_vtl(), 'assets', 'scripts', 'launch-osd.sh')
    threading.Thread(
        target=lambda: subprocess.run(['bash', script], capture_output=True),
        daemon=True,
    ).start()


# ── Small helpers ─────────────────────────────────────────────────────────────

def _toggle_row(group, title, subtitle, cfg, key):
    row = Adw.ActionRow(title=title, subtitle=subtitle)
    sw  = Gtk.Switch()
    sw.set_valign(Gtk.Align.CENTER)
    sw.set_active(bool(cfg.get(key, True)))
    sw.connect('notify::active', lambda s, _: osd_config.save({key: s.get_active()}))
    row.add_suffix(sw)
    row.set_activatable_widget(sw)
    group.add(row)
    return sw


def _combo_row(group, title, subtitle, options: list[tuple[str, str]], cfg, key):
    """options: list of (config_value, display_label) pairs."""
    keys   = [k for k, _ in options]
    labels = [lbl for _, lbl in options]
    current = cfg.get(key, keys[0])
    idx = keys.index(current) if current in keys else 0
    row = Adw.ComboRow(title=title, subtitle=subtitle)
    row.set_model(Gtk.StringList.new(labels))
    row.set_selected(idx)
    row.connect('notify::selected',
                lambda r, _: osd_config.save({key: keys[r.get_selected()]}))
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


# ── Position grid ─────────────────────────────────────────────────────────────

_POSITIONS = [
    # (config_key, row, col, tooltip)
    ('top-left',      0, 0, 'Top-left'),
    ('top-center',    0, 1, 'Top-center'),
    ('top-right',     0, 2, 'Top-right'),
    ('center-left',   1, 0, 'Center-left  (vertical layout)'),
    (None,            1, 1, ''),            # disabled center cell
    ('center-right',  1, 2, 'Center-right  (vertical layout)'),
    ('bottom-left',   2, 0, 'Bottom-left'),
    ('bottom-center', 2, 1, 'Bottom-center'),
    ('bottom-right',  2, 2, 'Bottom-right'),
]

# Arrow symbols for the position buttons
_POS_SYMBOL = {
    'top-left':      '↖',
    'top-center':    '↑',
    'top-right':     '↗',
    'center-left':   '↕←',
    'center-right':  '→↕',
    'bottom-left':   '↙',
    'bottom-center': '↓',
    'bottom-right':  '↘',
}


def _build_position_group(cfg) -> Adw.PreferencesGroup:
    group = Adw.PreferencesGroup(
        title='Position',
        description='Where the OSD appears. Center-left / Center-right use a vertical '
                    'layout (bar fills upward). Changes take effect after restarting the OSD.')

    current = cfg.get('osd_position', 'bottom-center')

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

        symbol = _POS_SYMBOL.get(pos, pos)
        btn = Gtk.ToggleButton(label=symbol)
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
                osd_config.save({'osd_position': p})

        btn.connect('toggled', _on_toggled)
        grid.attach(btn, col, row, 1, 1)

    grid_row = Adw.PreferencesRow()
    grid_row.set_activatable(False)
    grid_row.set_child(grid)
    group.add(grid_row)

    # Style selector
    _combo_row(group, 'OSD Style',
               'Float: inset from the edge by the margin — '
               'Dock: flush against the screen edge, slides out like a drawer',
               [
                   ('float', 'Float'),
                   ('dock',  'Dock'),
               ], cfg, 'osd_style')

    # Restart button
    restart_btn = Gtk.Button(label='Restart OSD Daemon')
    restart_btn.add_css_class('pill')
    restart_btn.set_halign(Gtk.Align.CENTER)
    restart_btn.set_margin_top(4)
    restart_btn.set_margin_bottom(6)
    restart_btn.set_tooltip_text('Apply position + any other daemon changes')
    restart_btn.connect('clicked', lambda _: _restart_osd())
    restart_row = Adw.PreferencesRow()
    restart_row.set_activatable(False)
    restart_row.set_child(restart_btn)
    group.add(restart_row)

    return group


# ── Page ──────────────────────────────────────────────────────────────────────

class OsdPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__()
        self._build()

    def _build(self):
        cfg = osd_config.load()

        # ── Position ─────────────────────────────────────────────────────────
        self.add(_build_position_group(cfg))

        # ── Volume ───────────────────────────────────────────────────────────
        vol = Adw.PreferencesGroup(title='Volume OSD')
        _toggle_row(vol, 'Enable', 'Show OSD when volume changes', cfg, 'osd_volume')
        _combo_row(vol, 'Display mode', 'What to show on the banner', [
            ('bar_and_value', 'Bar + value'),
            ('bar_only',      'Bar only'),
            ('value_only',    'Value only'),
        ], cfg, 'volume_display')
        _toggle_row(vol, 'Show device name',
                    'Display the active audio output device below the bar',
                    cfg, 'show_device')
        self.add(vol)

        # ── Brightness ───────────────────────────────────────────────────────
        bri = Adw.PreferencesGroup(title='Brightness OSD')
        _toggle_row(bri, 'Enable', 'Show OSD when brightness changes', cfg, 'osd_brightness')
        _combo_row(bri, 'Display mode', 'What to show on the banner', [
            ('bar_and_value', 'Bar + value'),
            ('bar_only',      'Bar only'),
            ('value_only',    'Value only'),
        ], cfg, 'brightness_display')
        self.add(bri)

        # ── Workspace ────────────────────────────────────────────────────────
        ws = Adw.PreferencesGroup(title='Workspace OSD')
        _toggle_row(ws, 'Enable', 'Show OSD when switching workspaces', cfg, 'osd_workspace')
        _toggle_row(ws, 'Same monitor only',
                    'Only trigger when the workspace changes on the active monitor, '
                    'not just from moving the cursor to another screen',
                    cfg, 'osd_workspace_local_only')
        _combo_row(ws, 'Display mode', 'What to show on the banner', [
            ('dots_only',        'Dots only'),
            ('number_only',      'Number only'),
            ('dots_and_number',  'Dots + number'),
        ], cfg, 'workspace_display')
        self.add(ws)

        # ── Appearance ───────────────────────────────────────────────────────
        app = Adw.PreferencesGroup(
            title='Appearance',
            description='Size and timing of the banner. Changes apply the next time the OSD appears.')
        _spin_row(app, 'Display duration', 'How long the banner stays visible (seconds)',
                  cfg['duration_ms'] / 1000.0, 0.5, 6.0, 0.1, 1,
                  lambda v: osd_config.save({'duration_ms': int(round(v * 1000))}))
        _spin_row(app, 'Edge margin', 'Gap from the screen edge (px)',
                  cfg['margin_px'], 0, 600, 10, 0,
                  lambda v: osd_config.save({'margin_px': int(v)}))
        _spin_row(app, 'Width', 'Banner width for horizontal positions (px)',
                  cfg['width_px'], 100, 900, 10, 0,
                  lambda v: osd_config.save({'width_px': int(v)}))
        _spin_row(app, 'Height', 'Banner height for horizontal positions (px)',
                  cfg['height_px'], 24, 200, 4, 0,
                  lambda v: osd_config.save({'height_px': int(v)}))
        self.add(app)
