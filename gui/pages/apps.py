from __future__ import annotations
import gi, os, shutil, subprocess, re, threading
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
gi.require_version('Gio', '2.0')
from gi.repository import Gtk, Adw, Gio

from models.hyprland import (
    parse_peripherals, generate_peripherals_section,
    parse_roleapps, generate_roleapps_section,
    ensure_roleapps_section,
    read_user_settings, write_user_settings, _write_section,
)

# ── App role definitions ──────────────────────────────────────────────────────
# Each entry: (config_key, label, fallback_icon, [(binary, display_name), ...])

_ROLE_APPS: list[tuple[str, str, str, list[tuple[str, str]]]] = [
    ('terminal',     'Terminal',       'utilities-terminal-symbolic', [
        ('kitty',          'Kitty'),
        ('alacritty',      'Alacritty'),
        ('foot',           'Foot'),
        ('ghostty',        'Ghostty'),
        ('wezterm',        'WezTerm'),
        ('konsole',        'Konsole'),
        ('gnome-terminal', 'GNOME Terminal'),
    ]),
    ('browser',      'Browser',        'web-browser-symbolic', [
        ('librewolf',            'LibreWolf'),
        ('firefox',              'Firefox'),
        ('chromium',             'Chromium'),
        ('brave',                'Brave'),
        ('vivaldi',              'Vivaldi'),
        ('google-chrome-stable', 'Google Chrome'),
    ]),
    ('filemanager',  'File Manager',   'system-file-manager-symbolic', [
        ('thunar',   'Thunar'),
        ('nautilus', 'Nautilus'),
        ('dolphin',  'Dolphin'),
        ('nemo',     'Nemo'),
        ('pcmanfm',  'PCManFM'),
    ]),
    ('messenger',    'Messenger',      'user-available-symbolic', [
        ('telegram-desktop', 'Telegram'),
        ('element-desktop',  'Element'),
        ('discord',          'Discord'),
        ('signal-desktop',   'Signal'),
        ('slack',            'Slack'),
    ]),
    ('player',       'Music Player',   'audio-x-generic-symbolic', [
        ('strawberry',   'Strawberry'),
        ('rhythmbox',    'Rhythmbox'),
        ('lollypop',     'Lollypop'),
        ('clementine',   'Clementine'),
        ('elisa',        'Elisa'),
    ]),
    ('notes_app',    'Notes',          'text-editor-symbolic', [
        ('obsidian', 'Obsidian'),
        ('logseq',   'Logseq'),
        ('joplin',   'Joplin'),
    ]),
    ('mail_app',     'Mail',           'mail-read-symbolic', [
        ('thunderbird', 'Thunderbird'),
        ('evolution',   'Evolution'),
        ('geary',       'Geary'),
    ]),
    ('calendar_app', 'Calendar',       'calendar-symbolic', [
        ('gnome-calendar', 'GNOME Calendar'),
        ('korganizer',     'KOrganizer'),
    ]),
    ('clock_app',    'Clock',          'alarm-symbolic', [
        ('gnome-clocks', 'GNOME Clocks'),
        ('kclock',       'KClock'),
    ]),
    ('tasks_app',    'Tasks',          'view-list-symbolic', [
        ('planify',    'Planify'),
        ('gnome-todo', 'GNOME To Do'),
    ]),
    ('editor_app',   'Text Editor',    'text-x-generic-symbolic', [
        ('neovide',  'Neovide'),
        ('codium',   'VSCodium'),
        ('zeditor',  'Zed'),
        ('kate',     'Kate'),
        ('gedit',    'Gedit'),
        ('mousepad', 'Mousepad'),
    ]),
    ('bitwarden',    'Password Manager', 'dialog-password-symbolic', [
        ('bitwarden',        'Bitwarden'),
        ('keepassxc',        'KeePassXC'),
        ('1password',        '1Password'),
    ]),
    ('screen_record', 'Screen Recorder', 'media-record-symbolic', [
        ('kooha',         'Kooha'),
        ('obs',           'OBS Studio'),
        ('simplescreenrecorder', 'SimpleScreenRecorder'),
        ('kazam',         'Kazam'),
    ]),
]

# System commands (text entry, no app-picker needed)
_SYS_CMDS: list[tuple[str, str, str, str]] = [
    ('wifi_menu',      'Wi-Fi Menu',          'network-wireless-symbolic',
     'Command or script to open a Wi-Fi selector (e.g. a rofi network menu)'),
    ('bluetooth_menu', 'Bluetooth Menu',      'bluetooth-symbolic',
     'Command or script to open a Bluetooth selector'),
    ('vpn_toggle',     'VPN Toggle',          'network-vpn-symbolic',
     'Command to connect/disconnect VPN (e.g. a WireGuard toggle script)'),
    ('audio_switch',   'Audio Output',        'audio-speakers-symbolic',
     'Command to cycle or switch the default audio output device'),
    ('mic_mute',       'Mic Mute',            'microphone-sensitivity-muted-symbolic',
     'Command to toggle microphone mute (default: pactl)'),
    ('night_light',    'Night Light',         'night-light-symbolic',
     'Command to toggle night light / colour temperature adjustment'),
    ('dnd_toggle',     'Do Not Disturb',      'notifications-disabled-symbolic',
     'Command to toggle DND (default: swaync-client --toggle-dnd)'),
]

_BROWSER_DESKTOP = {
    'librewolf':            'librewolf.desktop',
    'firefox':              'firefox.desktop',
    'chromium':             'chromium.desktop',
    'brave':                'brave-browser.desktop',
    'vivaldi':              'vivaldi-stable.desktop',
    'google-chrome-stable': 'google-chrome.desktop',
}


# ── App-info cache — preloaded in a background thread at import time ──────────

_gio_cache: dict[str, Gio.AppInfo | None] | None = None
_gio_ready  = threading.Event()


def _load_gio() -> None:
    global _gio_cache
    cache: dict[str, Gio.AppInfo | None] = {}
    for app in Gio.AppInfo.get_all():
        exe = app.get_executable()
        if exe:
            base = os.path.basename(exe)
            if base not in cache:
                cache[base] = app
    _gio_cache = cache
    _gio_ready.set()


threading.Thread(target=_load_gio, daemon=True, name='gio-preload').start()


def _gio_cache_get() -> dict[str, Gio.AppInfo | None]:
    _gio_ready.wait()   # instant if already done, blocks only on first page visit
    return _gio_cache   # type: ignore[return-value]


def _icon_for(binary: str) -> str | None:
    cache = _gio_cache_get()
    app = cache.get(os.path.basename(binary))
    if app:
        icon = app.get_icon()
        if icon:
            try:
                return icon.to_string()
            except Exception:
                pass
    return None


def _installed(candidates: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """Return only the (binary, label) pairs whose binary exists on PATH,
    keeping the original order. Always includes at least the first entry
    so the dropdown is never empty."""
    found = [(b, l) for b, l in candidates if shutil.which(b)]
    return found if found else [candidates[0]]


# ── Widget helpers ────────────────────────────────────────────────────────────

def _make_icon(binary: str, fallback: str) -> Gtk.Image:
    img = Gtk.Image()
    img.set_pixel_size(20)
    icon_str = _icon_for(binary)
    img.set_from_icon_name(icon_str if icon_str else fallback)
    return img


# ── Apps page ─────────────────────────────────────────────────────────────────

class AppsPage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._content  = read_user_settings()
        self._periph   = parse_peripherals(self._content)
        self._roleapps = parse_roleapps(self._content)

        self._stack = Gtk.Stack()
        self._stack.set_vexpand(True)
        self._stack.add_named(self._build_page(), 'main')
        self.append(self._stack)

    def _build_page(self) -> Adw.PreferencesPage:
        page = Adw.PreferencesPage()

        # ── Role Apps ─────────────────────────────────────────────────────────
        role_group = Adw.PreferencesGroup(
            title='Role Apps',
            description='Each role maps to a keybind in the Apps submap '
                        '(SUPER+grave → A). Changes apply after "Apply & Reload".')
        for key, label, fallback_icon, candidates in _ROLE_APPS:
            row = self._make_app_row(key, label, fallback_icon, candidates)
            role_group.add(row)
        page.add(role_group)

        # ── System Commands ───────────────────────────────────────────────────
        sys_group = Adw.PreferencesGroup(
            title='System Commands',
            description='Commands for the System submap (SUPER+grave → S). '
                        'Leave empty to disable that submap slot.')
        for key, label, icon, subtitle in _SYS_CMDS:
            row = self._make_cmd_row(key, label, icon, subtitle)
            sys_group.add(row)
        page.add(sys_group)

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

    # ── Row builders ──────────────────────────────────────────────────────────

    def _make_app_row(self, key: str, label: str,
                      fallback_icon: str,
                      candidates: list[tuple[str, str]]) -> Adw.ExpanderRow:
        installed  = _installed(candidates)
        binaries   = [b for b, _ in installed]
        app_labels = [l for _, l in installed]

        data       = {**self._periph, **self._roleapps}
        stored     = data.get(key, '')
        stored_bin = stored.split()[0] if stored else ''
        cur_idx    = binaries.index(stored_bin) if stored_bin in binaries else 0

        prefix_img = _make_icon(binaries[cur_idx], fallback_icon)

        expander = Adw.ExpanderRow(title=label)
        expander.set_subtitle(stored)
        expander.add_prefix(prefix_img)

        # ── Custom command entry (this is the stored value) ──────────────────
        entry = Adw.EntryRow(title='Custom command')
        entry.set_text(stored)

        # ── Quick-pick combo (pre-fills the entry) ───────────────────────────
        combo = Adw.ComboRow(title='Quick pick')
        combo.set_model(Gtk.StringList.new(app_labels))
        combo.set_selected(cur_idx)

        _updating = [False]

        def on_entry_changed(e):
            if _updating[0]:
                return
            val = e.get_text().strip()
            expander.set_subtitle(val)
            # Sync combo to match binary if possible
            bin_part = val.split()[0] if val else ''
            if bin_part in binaries:
                _updating[0] = True
                combo.set_selected(binaries.index(bin_part))
                icon_str = _icon_for(bin_part)
                prefix_img.set_from_icon_name(icon_str or fallback_icon)
                _updating[0] = False
            self._store(key, val)

        def on_combo_changed(c, _):
            if _updating[0]:
                return
            binary = binaries[c.get_selected()]
            icon_str = _icon_for(binary)
            prefix_img.set_from_icon_name(icon_str or fallback_icon)
            _updating[0] = True
            entry.set_text(binary)
            _updating[0] = False
            expander.set_subtitle(binary)
            self._store(key, binary)

        entry.connect('changed', on_entry_changed)
        combo.connect('notify::selected', on_combo_changed)

        expander.add_row(entry)
        expander.add_row(combo)
        return expander

    def _make_cmd_row(self, key: str, label: str,
                      icon: str, subtitle: str) -> Adw.EntryRow:
        data  = {**self._periph, **self._roleapps}
        value = data.get(key, '')
        row   = Adw.EntryRow(title=label)
        row.set_text(value)
        row.set_tooltip_text(subtitle)
        img = Gtk.Image.new_from_icon_name(icon)
        img.set_pixel_size(20)
        row.add_prefix(img)
        row.connect('changed', lambda r: self._store(key, r.get_text()))
        return row

    # ── State helpers ─────────────────────────────────────────────────────────

    def _store(self, key: str, value: str):
        """Write key/value to whichever dict owns it (periph or roleapps)."""
        from models.hyprland import _ROLEAPPS_KEYS as _RK
        if key in _RK:
            self._roleapps[key] = value
        else:
            self._periph[key] = value

    # ── Apply ─────────────────────────────────────────────────────────────────

    def _apply(self, _):
        content = self._content
        content = _write_section(content, 'PERIPHERALS',
                                 generate_peripherals_section(self._periph))
        content = ensure_roleapps_section(content)
        content = _write_section(content, 'ROLEAPPS',
                                 generate_roleapps_section(self._roleapps))
        write_user_settings(content)
        self._content = content

        # Set system browser default
        browser = self._periph.get('browser', '')
        desktop = _BROWSER_DESKTOP.get(browser, '')
        if desktop:
            subprocess.Popen(['xdg-settings', 'set', 'default-web-browser', desktop])

        subprocess.Popen(['hyprctl', 'reload'])
