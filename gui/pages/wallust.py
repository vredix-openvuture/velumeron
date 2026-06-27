import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw, GLib
import os, subprocess, threading

from constants import WALLUST_FIXED_DIR, WALLUST_MODE_FILE, VTL

_WALLUST_CONFIG_DIR = f"{VTL}/wallust"
_HOOKS_SH           = f"{VTL}/assets/scripts/wallust/hyprland_lua-colors.sh"


def _run_hooks() -> None:
    """Run the wallust post-processing hooks that wallust cs may skip."""
    subprocess.run(['bash', _HOOKS_SH], capture_output=True)
    subprocess.run(['hyprctl', 'reload'], capture_output=True)
    subprocess.Popen(['bash', '-c', 'pywalfox update'],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Full restart, not SIGUSR2: waybar's palette lives in an @imported
    # colors_gtk.css and SIGUSR2 only reloads the top-level style.css, so a
    # signal would leave the bar with the old colours.
    subprocess.Popen(
        ['bash', f'{VTL}/assets/scripts/launch-waybar.sh'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _read_mode() -> tuple[str, str]:
    """Returns (mode, scheme) — mode is 'auto' or 'fixed'."""
    try:
        raw = open(WALLUST_MODE_FILE).read().strip()
    except FileNotFoundError:
        return 'auto', ''
    if raw.startswith('fixed:'):
        return 'fixed', raw[6:]
    return 'auto', ''


def _write_mode(mode: str, scheme: str = '') -> None:
    os.makedirs(os.path.dirname(WALLUST_MODE_FILE), exist_ok=True)
    content = f'fixed:{scheme}\n' if mode == 'fixed' and scheme else 'auto\n'
    with open(WALLUST_MODE_FILE, 'w') as f:
        f.write(content)


def _list_schemes() -> list[str]:
    try:
        return sorted(f for f in os.listdir(WALLUST_FIXED_DIR) if f.endswith('.json'))
    except FileNotFoundError:
        return []


class WallustPage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._schemes: list[str] = []

        pref_page = Adw.PreferencesPage()
        pref_page.set_vexpand(True)

        group = Adw.PreferencesGroup()
        group.set_title('Wallust – Color Generation')
        group.set_description(
            'Choose whether colors are automatically generated from the wallpaper '
            'or loaded from a fixed scheme on each wallpaper change.'
        )

        self._switch_row = Adw.SwitchRow()
        self._switch_row.set_title('Automatic Color Generation')
        self._switch_row.set_subtitle('Derive colors from the wallpaper image on each change')
        group.add(self._switch_row)

        self._scheme_row = Adw.ComboRow()
        self._scheme_row.set_title('Fixed Color Scheme')
        group.add(self._scheme_row)

        pref_page.add(group)
        self.append(pref_page)

        bar = Gtk.ActionBar()
        self._status = Gtk.Label(label='')
        self._status.add_css_class('caption')
        bar.pack_start(self._status)

        btn_folder = Gtk.Button(label='Open Folder')
        btn_folder.add_css_class('flat')
        btn_folder.connect('clicked', self._on_open_folder)
        bar.pack_end(btn_folder)

        btn_reload = Gtk.Button(label='Refresh')
        btn_reload.connect('clicked', lambda _: self._load())
        bar.pack_end(btn_reload)

        btn_apply = Gtk.Button(label='Apply Settings')
        btn_apply.add_css_class('suggested-action')
        btn_apply.connect('clicked', self._on_apply)
        bar.pack_end(btn_apply)

        self.append(bar)

        self._switch_row.connect('notify::active', self._on_switch_changed)
        self._load()

    def _load(self) -> None:
        mode, saved_scheme = _read_mode()
        self._schemes = _list_schemes()

        string_list = Gtk.StringList()
        for s in self._schemes:
            # Display without .json extension
            string_list.append(os.path.splitext(s)[0])
        self._scheme_row.set_model(string_list)

        if self._schemes:
            self._scheme_row.set_subtitle(
                f'{len(self._schemes)} scheme(s) in fixed_colors/'
            )
            idx = self._schemes.index(saved_scheme) if saved_scheme in self._schemes else 0
            self._scheme_row.set_selected(idx)
        else:
            self._scheme_row.set_subtitle(
                'No .json files found in fixed_colors/'
            )

        self._switch_row.set_active(mode == 'auto')
        self._scheme_row.set_sensitive(mode == 'fixed' and bool(self._schemes))

    def _on_switch_changed(self, row, _) -> None:
        is_auto = row.get_active()
        self._scheme_row.set_sensitive(not is_auto and bool(self._schemes))

    def _on_apply(self, _) -> None:
        is_auto = self._switch_row.get_active()

        if is_auto:
            _write_mode('auto')
            self._status.set_text('Saved — automatic color generation active.')
            return

        if not self._schemes:
            self._status.set_text('No schemes found — add .json files to fixed_colors/.')
            return

        idx = self._scheme_row.get_selected()
        scheme = self._schemes[idx if idx < len(self._schemes) else 0]
        _write_mode('fixed', scheme)

        scheme_path = os.path.join(WALLUST_FIXED_DIR, scheme)
        self._status.set_text(f'Applying {os.path.splitext(scheme)[0]}…')

        def _apply():
            subprocess.run(
                ['wallust', '--config-dir', _WALLUST_CONFIG_DIR, 'cs', scheme_path],
                capture_output=True,
            )
            _run_hooks()
            GLib.idle_add(
                lambda: self._status.set_text(
                    f'{os.path.splitext(scheme)[0]} applied.'
                ) or False
            )

        threading.Thread(target=_apply, daemon=True).start()

    def _on_open_folder(self, _) -> None:
        os.makedirs(WALLUST_FIXED_DIR, exist_ok=True)
        subprocess.Popen(['xdg-open', WALLUST_FIXED_DIR])
