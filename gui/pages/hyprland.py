import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw
import subprocess
from constants import TRANSFORM_LABELS
from models.hyprland import (
    parse_monitors, generate_monitors_section,
    parse_peripherals, generate_peripherals_section,
    parse_autostart, generate_autostart_section,
    parse_windowrules, generate_windowrules_section,
    read_user_settings, write_user_settings,
    _write_section,
)


class MonitorRow(Adw.ExpanderRow):
    def __init__(self, mon):
        super().__init__(title=mon.output, subtitle=mon.mode)
        self.mon = mon
        self._build()

    def _build(self):
        mode_row = Adw.EntryRow(title='Modus')
        mode_row.set_text(self.mon.mode)
        def on_mode(r):
            self.mon.mode = r.get_text()
            self.set_subtitle(r.get_text())
        mode_row.connect('changed', on_mode)
        self.add_row(mode_row)

        scale_adj = Gtk.Adjustment(value=self.mon.scale, lower=0.25, upper=4.0,
                                   step_increment=0.25)
        scale_spin = Gtk.SpinButton(adjustment=scale_adj, digits=2)
        scale_spin.set_valign(Gtk.Align.CENTER)
        scale_spin.connect('value-changed', lambda w: setattr(self.mon, 'scale', w.get_value()))
        scale_row = Adw.ActionRow(title='Scale')
        scale_row.add_suffix(scale_spin)
        scale_row.set_activatable_widget(scale_spin)
        self.add_row(scale_row)

        tf_row = Adw.ComboRow(title='Transform',
                              model=Gtk.StringList.new(TRANSFORM_LABELS))
        tf_row.set_selected(self.mon.transform)
        tf_row.connect('notify::selected',
                       lambda r, _: setattr(self.mon, 'transform', r.get_selected()))
        self.add_row(tf_row)

        vrr_row = Adw.ComboRow(title='VRR (FreeSync/G-Sync)',
                               model=Gtk.StringList.new(['Aus (0)', 'An (1)', 'Force (2)']))
        vrr_row.set_selected(self.mon.vrr)
        vrr_row.connect('notify::selected',
                        lambda r, _: setattr(self.mon, 'vrr', r.get_selected()))
        self.add_row(vrr_row)

        bd_row = Adw.ComboRow(title='Farbtiefe',
                              model=Gtk.StringList.new(['8 Bit', '10 Bit']))
        bd_row.set_selected(0 if self.mon.bitdepth == 8 else 1)
        bd_row.connect('notify::selected',
                       lambda r, _: setattr(self.mon, 'bitdepth', [8, 10][r.get_selected()]))
        self.add_row(bd_row)

        pos_row = Adw.EntryRow(title='Position')
        pos_row.set_text(str(self.mon.position))
        pos_row.connect('changed', lambda r: setattr(self.mon, 'position', r.get_text()))
        self.add_row(pos_row)


class HyprlandPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__()
        self._content                       = read_user_settings()
        self._monitors                      = parse_monitors(self._content)
        self._periph                        = parse_peripherals(self._content)
        self._daemons, self._apps           = parse_autostart(self._content)
        self._float_pat, self._opacity_pat  = parse_windowrules(self._content)
        self._build()

    def _build(self):
        # ── Monitors ──────────────────────────────────────────────────────────
        mon_group = Adw.PreferencesGroup(title='Monitore')
        for mon in self._monitors:
            mon_group.add(MonitorRow(mon))
        self.add(mon_group)

        # ── Peripherals ───────────────────────────────────────────────────────
        per_group = Adw.PreferencesGroup(title='Tasten & Cursor')
        for var, label in [
            ('fn_brightness_up',   'Helligkeit +'),
            ('fn_brightness_down', 'Helligkeit −'),
            ('fn_volume_up',       'Lautstärke +'),
            ('fn_volume_down',     'Lautstärke −'),
            ('fn_volume_mute',     'Stummschalten'),
            ('fn_play_stop_play',  'Play / Pause'),
            ('fn_play_next',       'Nächster Titel'),
            ('fn_play_prev',       'Vorheriger Titel'),
        ]:
            row = Adw.EntryRow(title=label)
            row.set_text(str(self._periph.get(var, '')))
            row.connect('changed', lambda r, v=var: self._periph.__setitem__(v, r.get_text()))
            per_group.add(row)

        cur_row = Adw.EntryRow(title='Cursor-Theme')
        cur_row.set_text(str(self._periph.get('cur_theme', '')))
        cur_row.connect('changed',
                        lambda r: self._periph.__setitem__('cur_theme', r.get_text()))
        per_group.add(cur_row)

        cur_size_adj = Gtk.Adjustment(
            value=self._periph.get('cur_size', 20), lower=8, upper=128, step_increment=2)
        cur_size_spin = Gtk.SpinButton(adjustment=cur_size_adj, digits=0)
        cur_size_spin.set_valign(Gtk.Align.CENTER)
        cur_size_spin.connect('value-changed',
                              lambda w: self._periph.__setitem__('cur_size', int(w.get_value())))
        cur_size_row = Adw.ActionRow(title='Cursor-Größe')
        cur_size_row.add_suffix(cur_size_spin)
        per_group.add(cur_size_row)
        self.add(per_group)

        # ── Window Rules ──────────────────────────────────────────────────────
        wr_group = Adw.PreferencesGroup(title='Window Rules')
        float_row = Adw.EntryRow(title='Floating-Regex')
        float_row.set_text(self._float_pat)
        float_row.connect('changed', lambda r: setattr(self, '_float_pat', r.get_text()))
        wr_group.add(float_row)
        opacity_row = Adw.EntryRow(title='Opacity-Regex')
        opacity_row.set_text(self._opacity_pat)
        opacity_row.connect('changed', lambda r: setattr(self, '_opacity_pat', r.get_text()))
        wr_group.add(opacity_row)
        self.add(wr_group)

        # ── Startup Apps ──────────────────────────────────────────────────────
        self._apps_group = Adw.PreferencesGroup(title='Startup Apps')
        for app_entry in self._apps:
            self._apps_group.add(self._make_app_row(app_entry))
        add_btn = Gtk.Button(icon_name='list-add-symbolic')
        add_btn.add_css_class('flat')
        add_btn.connect('clicked', self._add_app)
        self._apps_group.set_header_suffix(add_btn)
        self.add(self._apps_group)

        # ── Apply ─────────────────────────────────────────────────────────────
        apply_group = Adw.PreferencesGroup()
        apply_btn = Gtk.Button(label='Änderungen übernehmen & Hyprland neu laden')
        apply_btn.add_css_class('suggested-action')
        apply_btn.add_css_class('pill')
        apply_btn.connect('clicked', self._apply)
        apply_group.add(apply_btn)
        self.add(apply_group)

    def _make_app_row(self, app_entry: dict) -> Adw.EntryRow:
        row = Adw.EntryRow(title=f'WS {app_entry["ws"]}')
        row.set_text(app_entry['app'])

        ws_adj = Gtk.Adjustment(value=app_entry['ws'], lower=1, upper=99, step_increment=1)
        ws_spin = Gtk.SpinButton(adjustment=ws_adj, digits=0)
        ws_spin.set_valign(Gtk.Align.CENTER)

        def on_ws(w):
            app_entry['ws'] = int(w.get_value())
            row.set_title(f'WS {app_entry["ws"]}')

        def on_app(r):
            app_entry['app'] = r.get_text()

        ws_spin.connect('value-changed', on_ws)
        row.connect('changed', on_app)
        row.add_suffix(ws_spin)
        return row

    def _add_app(self, _):
        new_entry = {'app': '', 'ws': 1}
        self._apps.append(new_entry)
        self._apps_group.add(self._make_app_row(new_entry))

    def _apply(self, _):
        content = self._content
        content = _write_section(content, 'MONITORS',
                                 generate_monitors_section(self._monitors))
        content = _write_section(content, 'PERIPHERALS',
                                 generate_peripherals_section(self._periph))
        content = _write_section(content, 'AUTOSTART',
                                 generate_autostart_section(self._daemons, self._apps))
        content = _write_section(content, 'WINDOWRULES',
                                 generate_windowrules_section(self._float_pat, self._opacity_pat))
        write_user_settings(content)
        self._content = content
        subprocess.Popen(['hyprctl', 'reload'])
