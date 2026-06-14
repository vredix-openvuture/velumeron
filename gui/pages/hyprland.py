import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw
import os, shutil, subprocess

# ── Keyboard layouts (XKB codes + display names) ─────────────────────────────

_KB_LAYOUTS: list[tuple[str, str]] = [
    ('eu',    'EurKey (eu)'),
    ('us',    'English US (us)'),
    ('gb',    'English UK (gb)'),
    ('de',    'Deutsch (de)'),
    ('at',    'Deutsch – Österreich (at)'),
    ('ch',    'Deutsch – Schweiz (ch)'),
    ('fr',    'Français / AZERTY (fr)'),
    ('be',    'Belgique / AZERTY (be)'),
    ('es',    'Español (es)'),
    ('latam', 'Español – Latam (latam)'),
    ('it',    'Italiano (it)'),
    ('pt',    'Português (pt)'),
    ('br',    'Português – Brasil (br)'),
    ('nl',    'Nederlands (nl)'),
    ('pl',    'Polski (pl)'),
    ('ru',    'Русский (ru)'),
    ('tr',    'Türkçe (tr)'),
    ('se',    'Svenska (se)'),
    ('no',    'Norsk (no)'),
    ('dk',    'Dansk (dk)'),
    ('fi',    'Suomi (fi)'),
    ('cz',    'Čeština (cz)'),
    ('sk',    'Slovenčina (sk)'),
    ('hu',    'Magyar (hu)'),
    ('ro',    'Română (ro)'),
    ('hr',    'Hrvatski (hr)'),
    ('jp',    'Japanese (jp)'),
    ('kr',    'Korean (kr)'),
    ('cn',    'Chinese (cn)'),
    ('ara',   'Arabic (ara)'),
    ('il',    'Hebrew (il)'),
]

_KB_CODES    = [c for c, _ in _KB_LAYOUTS]
_KB_LABELS   = [l for _, l in _KB_LAYOUTS]

# ── System locales ─────────────────────────────────────────────────────────────

_LOCALES: list[tuple[str, str]] = [
    ('en_US.UTF-8', 'English – US (en_US)'),
    ('en_GB.UTF-8', 'English – UK (en_GB)'),
    ('de_DE.UTF-8', 'Deutsch – Deutschland (de_DE)'),
    ('de_AT.UTF-8', 'Deutsch – Österreich (de_AT)'),
    ('de_CH.UTF-8', 'Deutsch – Schweiz (de_CH)'),
    ('fr_FR.UTF-8', 'Français – France (fr_FR)'),
    ('fr_BE.UTF-8', 'Français – Belgique (fr_BE)'),
    ('fr_CH.UTF-8', 'Français – Suisse (fr_CH)'),
    ('es_ES.UTF-8', 'Español – España (es_ES)'),
    ('es_MX.UTF-8', 'Español – México (es_MX)'),
    ('it_IT.UTF-8', 'Italiano (it_IT)'),
    ('pt_PT.UTF-8', 'Português – Portugal (pt_PT)'),
    ('pt_BR.UTF-8', 'Português – Brasil (pt_BR)'),
    ('nl_NL.UTF-8', 'Nederlands (nl_NL)'),
    ('pl_PL.UTF-8', 'Polski (pl_PL)'),
    ('ru_RU.UTF-8', 'Русский (ru_RU)'),
    ('tr_TR.UTF-8', 'Türkçe (tr_TR)'),
    ('sv_SE.UTF-8', 'Svenska (sv_SE)'),
    ('nb_NO.UTF-8', 'Norsk (nb_NO)'),
    ('da_DK.UTF-8', 'Dansk (da_DK)'),
    ('fi_FI.UTF-8', 'Suomi (fi_FI)'),
    ('cs_CZ.UTF-8', 'Čeština (cs_CZ)'),
    ('sk_SK.UTF-8', 'Slovenčina (sk_SK)'),
    ('hu_HU.UTF-8', 'Magyar (hu_HU)'),
    ('ro_RO.UTF-8', 'Română (ro_RO)'),
    ('hr_HR.UTF-8', 'Hrvatski (hr_HR)'),
    ('ja_JP.UTF-8', 'Japanese (ja_JP)'),
    ('ko_KR.UTF-8', 'Korean (ko_KR)'),
    ('zh_CN.UTF-8', 'Chinese Simplified (zh_CN)'),
    ('zh_TW.UTF-8', 'Chinese Traditional (zh_TW)'),
    ('ar_EG.UTF-8', 'Arabic (ar_EG)'),
]

_LOCALE_CODES  = [c for c, _ in _LOCALES]
_LOCALE_LABELS = [l for _, l in _LOCALES]

_LOCALE_ENV_FILE = os.path.join(
    os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config')),
    'environment.d', '50-vutureland-locale.conf'
)
from constants import TRANSFORM_LABELS
from models.hyprland import (
    parse_monitors, generate_monitors_section,
    parse_peripherals, generate_peripherals_section,
    parse_autostart, generate_autostart_section,
    parse_windowrules, generate_windowrules_section,
    parse_rule_entries, build_rule_pattern,
    parse_lookandfeel, generate_lookandfeel_section, ensure_lookandfeel_section,
    LNF_DEFAULTS,
    read_user_settings, write_user_settings,
    _write_section,
)


# ── Cursor theme discovery ────────────────────────────────────────────────────

def _find_cursor_themes() -> list[str]:
    seen = set()
    themes = []
    dirs = [
        '/usr/share/icons',
        os.path.expanduser('~/.local/share/icons'),
    ]
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if name in seen:
                continue
            if os.path.isdir(os.path.join(d, name, 'cursors')):
                seen.add(name)
                themes.append(name)
    return themes or ['default']


# ── Installed app discovery ───────────────────────────────────────────────────

_KNOWN_TERMINALS = [
    ('kitty',     'Kitty'),
    ('alacritty', 'Alacritty'),
    ('foot',      'Foot'),
    ('wezterm',   'WezTerm'),
    ('ghostty',   'Ghostty'),
    ('konsole',   'Konsole'),
    ('gnome-terminal', 'GNOME Terminal'),
]

_KNOWN_BROWSERS = [
    ('librewolf', 'LibreWolf'),
    ('firefox',   'Firefox'),
    ('chromium',  'Chromium'),
    ('brave',     'Brave'),
    ('vivaldi',   'Vivaldi'),
    ('google-chrome-stable', 'Google Chrome'),
]

_BROWSER_DESKTOP = {
    'librewolf': 'librewolf.desktop',
    'firefox':   'firefox.desktop',
    'chromium':  'chromium.desktop',
    'brave':     'brave-browser.desktop',
    'vivaldi':   'vivaldi-stable.desktop',
    'google-chrome-stable': 'google-chrome.desktop',
}


def _installed_apps(candidates: list[tuple[str, str]]) -> list[tuple[str, str]]:
    result = [(b, l) for b, l in candidates if shutil.which(b)]
    return result or [candidates[0]]


def _vtl_user_dir() -> str:
    xdg = os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config'))
    return os.environ.get('VUTURELAND_USER_DIR', os.path.join(xdg, 'vutureland'))


def _terminal_cmd(binary: str) -> str:
    if binary == 'kitty':
        return f'kitty -c {_vtl_user_dir()}/kitty/kitty.conf'
    return binary


class MonitorRow(Adw.ExpanderRow):
    def __init__(self, mon):
        super().__init__(title=mon.output, subtitle=mon.mode)
        self.mon = mon
        self._build()

    def _build(self):
        mode_row = Adw.EntryRow(title='Mode')
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
                               model=Gtk.StringList.new(['Off (0)', 'On (1)', 'Force (2)']))
        vrr_row.set_selected(self.mon.vrr)
        vrr_row.connect('notify::selected',
                        lambda r, _: setattr(self.mon, 'vrr', r.get_selected()))
        self.add_row(vrr_row)

        bd_row = Adw.ComboRow(title='Bit Depth',
                              model=Gtk.StringList.new(['8 Bit', '10 Bit']))
        bd_row.set_selected(0 if self.mon.bitdepth == 8 else 1)
        bd_row.connect('notify::selected',
                       lambda r, _: setattr(self.mon, 'bitdepth', [8, 10][r.get_selected()]))
        self.add_row(bd_row)

        pos_row = Adw.EntryRow(title='Position')
        pos_row.set_text(str(self.mon.position))
        pos_row.connect('changed', lambda r: setattr(self.mon, 'position', r.get_text()))
        self.add_row(pos_row)


class HyprlandPage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._content                       = read_user_settings()
        self._monitors                      = parse_monitors(self._content)
        self._periph                        = parse_peripherals(self._content)
        self._daemons, self._apps           = parse_autostart(self._content)
        self._float_pat, self._opacity_pat  = parse_windowrules(self._content)
        self._float_names   = parse_rule_entries(self._float_pat)
        self._opacity_names = parse_rule_entries(self._opacity_pat)
        self._lnf           = {**LNF_DEFAULTS, **parse_lookandfeel(self._content)}

        # Stack so the window-rule list editor can be shown as an in-panel
        # subpage (a separate window can't be used under the layer-shell panel).
        self._stack = Gtk.Stack()
        self._stack.set_vexpand(True)
        self._stack.add_named(self._build_main(), 'main')
        self.append(self._stack)

    @staticmethod
    def _rule_summary(names: list) -> str:
        names = sorted((n for n in names if n.strip()), key=str.lower)
        return ', '.join(names) if names else 'None'

    def _build_main(self) -> Adw.PreferencesPage:
        page = Adw.PreferencesPage()

        # ── Monitors ──────────────────────────────────────────────────────────
        mon_group = Adw.PreferencesGroup(title='Monitors')
        for mon in self._monitors:
            mon_group.add(MonitorRow(mon))
        page.add(mon_group)

        # ── Cursor ────────────────────────────────────────────────────────────
        per_group = Adw.PreferencesGroup(title='Cursor')

        cursor_themes = _find_cursor_themes()
        cur_theme_val = self._periph.get('cur_theme', 'breeze_cursors')
        cur_theme_idx = cursor_themes.index(cur_theme_val) if cur_theme_val in cursor_themes else 0
        cur_theme_row = Adw.ComboRow(title='Cursor Theme')
        cur_theme_row.set_model(Gtk.StringList.new(cursor_themes))
        cur_theme_row.set_selected(cur_theme_idx)
        cur_theme_row.connect('notify::selected',
                              lambda r, _: self._periph.__setitem__(
                                  'cur_theme', cursor_themes[r.get_selected()]))
        per_group.add(cur_theme_row)

        _CURSOR_SIZES = [16, 20, 24, 28, 32, 40, 48, 64]
        cur_size_val = self._periph.get('cur_size', 24)
        cur_size_idx = _CURSOR_SIZES.index(cur_size_val) if cur_size_val in _CURSOR_SIZES else 2
        cur_size_row = Adw.ComboRow(title='Cursor Size')
        cur_size_row.set_model(Gtk.StringList.new([str(s) for s in _CURSOR_SIZES]))
        cur_size_row.set_selected(cur_size_idx)
        cur_size_row.connect('notify::selected',
                             lambda r, _: self._periph.__setitem__(
                                 'cur_size', _CURSOR_SIZES[r.get_selected()]))
        per_group.add(cur_size_row)
        page.add(per_group)

        # ── Default Apps ──────────────────────────────────────────────────────
        apps_group = Adw.PreferencesGroup(
            title='Default Apps',
            description='Changes apply after "Apply & Reload Hyprland". '
                        'The browser is also set as the system XDG default.')

        installed_terms = _installed_apps(_KNOWN_TERMINALS)
        term_binaries   = [b for b, _ in installed_terms]
        term_labels     = [l for _, l in installed_terms]
        stored_term_cmd = self._periph.get('terminal', '')
        cur_term_binary = stored_term_cmd.split()[0] if stored_term_cmd else ''
        cur_term_idx    = (term_binaries.index(cur_term_binary)
                           if cur_term_binary in term_binaries else 0)
        # Ensure a default is always set so Apply never writes an empty terminal
        self._periph['terminal'] = _terminal_cmd(term_binaries[cur_term_idx])
        term_row = Adw.ComboRow(title='Terminal')
        term_row.set_model(Gtk.StringList.new(term_labels))
        term_row.set_selected(cur_term_idx)
        def _on_term(r, _):
            self._periph['terminal'] = _terminal_cmd(term_binaries[r.get_selected()])
        term_row.connect('notify::selected', _on_term)
        apps_group.add(term_row)

        installed_brows = _installed_apps(_KNOWN_BROWSERS)
        brow_binaries   = [b for b, _ in installed_brows]
        brow_labels     = [l for _, l in installed_brows]
        stored_browser  = self._periph.get('browser', '')
        cur_brow_idx    = (brow_binaries.index(stored_browser)
                           if stored_browser in brow_binaries else 0)
        # Ensure a default is always set
        self._periph['browser'] = brow_binaries[cur_brow_idx]
        brow_row = Adw.ComboRow(title='Browser')
        brow_row.set_model(Gtk.StringList.new(brow_labels))
        brow_row.set_selected(cur_brow_idx)
        brow_row.connect('notify::selected',
                         lambda r, _: self._periph.__setitem__(
                             'browser', brow_binaries[r.get_selected()]))
        apps_group.add(brow_row)
        page.add(apps_group)

        # ── Window Rules (open a list editor subpage) ─────────────────────────
        wr_group = Adw.PreferencesGroup(title='Window Rules')
        self._float_row = Adw.ActionRow(
            title='Floating', subtitle=self._rule_summary(self._float_names))
        self._float_row.add_suffix(Gtk.Image.new_from_icon_name('go-next-symbolic'))
        self._float_row.set_activatable(True)
        self._float_row.connect('activated', lambda r: self._open_rule_editor('float'))
        wr_group.add(self._float_row)

        self._opacity_row = Adw.ActionRow(
            title='Opacity', subtitle=self._rule_summary(self._opacity_names))
        self._opacity_row.add_suffix(Gtk.Image.new_from_icon_name('go-next-symbolic'))
        self._opacity_row.set_activatable(True)
        self._opacity_row.connect('activated', lambda r: self._open_rule_editor('opacity'))
        wr_group.add(self._opacity_row)
        page.add(wr_group)

        # ── Look and Feel ─────────────────────────────────────────────────────
        # Overrides the defaults in hypr.lua/modules/look_and_feel.lua via
        # user_settings.lua. Left untouched, the hypr.lua defaults apply.
        lnf_group = Adw.PreferencesGroup(
            title='Look and Feel',
            description='Overrides the Hyprland defaults. Reset to the defaults '
                        f'({LNF_DEFAULTS["lnf_rounding"]} / {LNF_DEFAULTS["lnf_border_size"]}) '
                        'to fall back to hypr.lua.')

        radius_adj = Gtk.Adjustment(value=self._lnf['lnf_rounding'],
                                    lower=0, upper=40, step_increment=1)
        radius_spin = Gtk.SpinButton(adjustment=radius_adj, digits=0)
        radius_spin.set_valign(Gtk.Align.CENTER)
        radius_spin.connect('value-changed',
                            lambda w: self._lnf.__setitem__('lnf_rounding', int(w.get_value())))
        radius_row = Adw.ActionRow(title='Border Radius', subtitle='Corner rounding (px)')
        radius_row.add_suffix(radius_spin)
        lnf_group.add(radius_row)

        bsize_adj = Gtk.Adjustment(value=self._lnf['lnf_border_size'],
                                   lower=0, upper=10, step_increment=1)
        bsize_spin = Gtk.SpinButton(adjustment=bsize_adj, digits=0)
        bsize_spin.set_valign(Gtk.Align.CENTER)
        bsize_spin.connect('value-changed',
                           lambda w: self._lnf.__setitem__('lnf_border_size', int(w.get_value())))
        bsize_row = Adw.ActionRow(title='Border Size', subtitle='Window border thickness (px)')
        bsize_row.add_suffix(bsize_spin)
        lnf_group.add(bsize_row)
        page.add(lnf_group)

        # ── Keyboard & Language ───────────────────────────────────────────────
        kb_group = Adw.PreferencesGroup(
            title='Keyboard & Language',
            description='Keyboard layout takes effect immediately after "Apply". '
                        'The system locale is written to ~/.config/environment.d/ '
                        'and applies on next login.')

        cur_kb  = self._periph.get('kb_layout',  'eu')
        kb_idx  = _KB_CODES.index(cur_kb) if cur_kb in _KB_CODES else 0
        kb_row  = Adw.ComboRow(title='Keyboard Layout')
        kb_row.set_model(Gtk.StringList.new(_KB_LABELS))
        kb_row.set_selected(kb_idx)
        kb_row.connect('notify::selected',
                       lambda r, _: self._periph.__setitem__(
                           'kb_layout', _KB_CODES[r.get_selected()]))
        kb_group.add(kb_row)

        cur_loc  = self._periph.get('sys_locale', 'en_US.UTF-8')
        loc_idx  = _LOCALE_CODES.index(cur_loc) if cur_loc in _LOCALE_CODES else 0
        loc_row  = Adw.ComboRow(title='System Language')
        loc_row.set_model(Gtk.StringList.new(_LOCALE_LABELS))
        loc_row.set_selected(loc_idx)
        loc_row.connect('notify::selected',
                        lambda r, _: self._periph.__setitem__(
                            'sys_locale', _LOCALE_CODES[r.get_selected()]))
        kb_group.add(loc_row)
        page.add(kb_group)

        # ── Startup Apps ──────────────────────────────────────────────────────
        self._apps_group = Adw.PreferencesGroup(title='Startup Apps')
        for app_entry in self._apps:
            self._apps_group.add(self._make_app_row(app_entry))
        add_btn = Gtk.Button(icon_name='list-add-symbolic')
        add_btn.add_css_class('flat')
        add_btn.connect('clicked', self._add_app)
        self._apps_group.set_header_suffix(add_btn)
        page.add(self._apps_group)

        # ── Apply ─────────────────────────────────────────────────────────────
        apply_group = Adw.PreferencesGroup()
        apply_btn = Gtk.Button(label='Apply & Reload Hyprland')
        apply_btn.add_css_class('suggested-action')
        apply_btn.add_css_class('pill')
        apply_btn.set_halign(Gtk.Align.CENTER)
        apply_btn.connect('clicked', self._apply)
        apply_group.add(apply_btn)
        page.add(apply_group)
        return page

    # ── Window-rule list editor (in-panel subpage) ────────────────────────────

    def _open_rule_editor(self, kind: str):
        names = self._float_names if kind == 'float' else self._opacity_names
        self._editing_kind = kind
        self._rule_rows = []

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                         margin_start=12, margin_end=12, margin_top=10, margin_bottom=6)
        back = Gtk.Button(icon_name='go-previous-symbolic')
        back.add_css_class('flat')
        back.connect('clicked', lambda _: self._close_rule_editor())
        header.append(back)
        title = Gtk.Label(
            label='Floating windows' if kind == 'float' else 'Reduced-opacity windows')
        title.add_css_class('title-4')
        header.append(title)

        group = Adw.PreferencesGroup(
            title='Apps',
            description='Type an app name (e.g. kitty). Matching is case-insensitive.')
        add = Gtk.Button(icon_name='list-add-symbolic')
        add.add_css_class('flat')
        add.connect('clicked', lambda _: self._rule_add_row(group, ''))
        group.set_header_suffix(add)
        self._editing_group = group
        for n in sorted((x for x in names if x.strip()), key=str.lower):
            self._rule_add_row(group, n)

        page = Adw.PreferencesPage()
        page.add(group)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(header)
        box.append(page)

        old = self._stack.get_child_by_name('wr-edit')
        if old is not None:
            self._stack.remove(old)
        self._stack.add_named(box, 'wr-edit')
        self._stack.set_visible_child_name('wr-edit')

    def _rule_add_row(self, group, text: str):
        row = Adw.EntryRow(title='App name')
        row.set_text(text)
        rm = Gtk.Button(icon_name='list-remove-symbolic')
        rm.add_css_class('flat')
        rm.set_valign(Gtk.Align.CENTER)
        def _remove(_):
            group.remove(row)
            if row in self._rule_rows:
                self._rule_rows.remove(row)
        rm.connect('clicked', _remove)
        row.add_suffix(rm)
        group.add(row)
        self._rule_rows.append(row)

    def _close_rule_editor(self):
        names = [r.get_text().strip() for r in self._rule_rows if r.get_text().strip()]
        if self._editing_kind == 'float':
            self._float_names = names
            self._float_pat = build_rule_pattern(names)
            self._float_row.set_subtitle(self._rule_summary(names))
        else:
            self._opacity_names = names
            self._opacity_pat = build_rule_pattern(names)
            self._opacity_row.set_subtitle(self._rule_summary(names))
        self._stack.set_visible_child_name('main')

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
        # Rebuild the regexes from the edited name lists (alphabetical, de-duped).
        self._float_pat   = build_rule_pattern(self._float_names)
        self._opacity_pat = build_rule_pattern(self._opacity_names)
        content = self._content
        content = _write_section(content, 'MONITORS',
                                 generate_monitors_section(self._monitors))
        content = _write_section(content, 'PERIPHERALS',
                                 generate_peripherals_section(self._periph))
        content = _write_section(content, 'AUTOSTART',
                                 generate_autostart_section(self._daemons, self._apps))
        content = _write_section(content, 'WINDOWRULES',
                                 generate_windowrules_section(self._float_pat, self._opacity_pat))
        content = ensure_lookandfeel_section(content)
        content = _write_section(content, 'LOOKANDFEEL',
                                 generate_lookandfeel_section(
                                     self._lnf['lnf_rounding'], self._lnf['lnf_border_size']))
        write_user_settings(content)
        self._content = content
        # Set system browser default
        browser = self._periph.get('browser', '')
        desktop = _BROWSER_DESKTOP.get(browser, '')
        if desktop:
            subprocess.Popen(['xdg-settings', 'set', 'default-web-browser', desktop])
        # Apply keyboard layout immediately (no reload needed)
        kb_layout = self._periph.get('kb_layout', 'eu')
        subprocess.Popen(['hyprctl', 'keyword', 'input:kb_layout', kb_layout])
        # Write system locale to environment.d (takes effect on next login)
        sys_locale = self._periph.get('sys_locale', 'en_US.UTF-8')
        try:
            os.makedirs(os.path.dirname(_LOCALE_ENV_FILE), exist_ok=True)
            with open(_LOCALE_ENV_FILE, 'w') as _f:
                _f.write(f'LANG={sys_locale}\nLC_ALL={sys_locale}\n')
        except OSError:
            pass
        subprocess.Popen(['hyprctl', 'reload'])
