from __future__ import annotations
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib
import os, re, json, subprocess, threading, time
from constants import (
    HYPRLOCK_THEMES, HYPRLOCK_CONF, HYPRLOCK_THUMB, HYPRLOCK_BLACK_WP,
    HYPRIDLE_CONF, POWERMODE_SH,
)


# ── Hyprlock helpers ──────────────────────────────────────────────────────────

def _bg_path(theme_file: str) -> str | None:
    in_block = False
    with open(theme_file) as f:
        for line in f:
            stripped = line.strip()
            if re.match(r'^background\s*\{', stripped):
                in_block = True
                continue
            if in_block:
                m = re.search(r'path\s*=\s*(.+)', stripped)
                if m:
                    path = m.group(1).strip()
                    return path.replace('~', os.path.expanduser('~'))
                if stripped == '}':
                    break
    return None


def _ensure_thumb(theme_file: str, name: str) -> str | None:
    os.makedirs(HYPRLOCK_THUMB, exist_ok=True)
    thumb = os.path.join(HYPRLOCK_THUMB, f'{name}.png')
    if os.path.exists(thumb):
        try:
            if os.path.getmtime(theme_file) <= os.path.getmtime(thumb):
                return thumb
        except OSError:
            pass

    bg = _bg_path(theme_file)
    tmp = None

    if bg == 'screenshot':
        tmp = f'/tmp/hyprlock-preview-{name}.png'
        result = subprocess.run(['grim', tmp], capture_output=True)
        bg_file = tmp if result.returncode == 0 and os.path.exists(tmp) else HYPRLOCK_BLACK_WP
    elif bg and os.path.exists(bg):
        bg_file = bg
    else:
        bg_file = HYPRLOCK_BLACK_WP

    subprocess.run([
        'magick', bg_file,
        '-resize', '400x240^',
        '-gravity', 'Center',
        '-extent', '400x240',
        f'PNG32:{thumb}',
    ], capture_output=True)

    if tmp and os.path.exists(tmp):
        try:
            os.unlink(tmp)
        except OSError:
            pass

    return thumb if os.path.exists(thumb) else None


def _apply_theme(theme_file: str) -> None:
    with open(theme_file) as f:
        content = f.read()

    try:
        result = subprocess.run(['hyprctl', 'monitors', '-j'], capture_output=True, text=True)
        monitors = json.loads(result.stdout)
        primary = next((m['name'] for m in monitors if m.get('focused')), None)
        if primary is None and monitors:
            primary = monitors[0]['name']
        others = [m['name'] for m in monitors if not m.get('focused')]
    except Exception:
        primary = 'eDP-1'
        others = []

    if primary:
        content = content.replace('{{mon1}}', primary)

    for i, mon in enumerate(others):
        n = i + 2
        placeholder = f'{{{{mon{n}}}}}'
        if placeholder in content:
            content = content.replace(placeholder, mon)
        else:
            content += (
                f'\nbackground {{\n'
                f'    monitor = {mon}\n'
                f'    path = {HYPRLOCK_BLACK_WP}\n'
                f'}}'
            )

    with open(HYPRLOCK_CONF, 'w') as f:
        f.write(content)

    # Remember the chosen theme so launch-hyprlock's monitor self-heal can
    # regenerate this exact theme (with the then-current monitors) if needed.
    try:
        name = os.path.splitext(os.path.basename(theme_file))[0]
        with open(os.path.join(os.path.dirname(HYPRLOCK_CONF), '.hyprlock-theme'), 'w') as f:
            f.write(name + '\n')
    except OSError:
        pass


# ── Hypridle helpers ──────────────────────────────────────────────────────────

def _read_hypridle() -> tuple[int, int]:
    try:
        with open(HYPRIDLE_CONF) as f:
            content = f.read()
        timeouts = [int(x) for x in re.findall(r'timeout\s*=\s*(\d+)', content)]
        return timeouts[0] if timeouts else 300, timeouts[1] if len(timeouts) > 1 else 1200
    except Exception:
        return 300, 1200


def _write_hypridle(lock_secs: int, suspend_secs: int) -> None:
    with open(HYPRIDLE_CONF) as f:
        content = f.read()
    vals = [str(lock_secs), str(suspend_secs)]
    count = [0]
    def _repl(m):
        i = count[0]; count[0] += 1
        return m.group(1) + vals[i] if i < len(vals) else m.group(0)
    new_content = re.sub(r'(timeout\s*=\s*)\d+', _repl, content)
    with open(HYPRIDLE_CONF, 'w') as f:
        f.write(new_content)


def _restart_hypridle() -> None:
    subprocess.run(['pkill', '-x', 'hypridle'], capture_output=True)
    time.sleep(0.4)
    subprocess.Popen(['hypridle'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ── Power mode helpers ────────────────────────────────────────────────────────

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


# ── Widgets ───────────────────────────────────────────────────────────────────

class ThemeCard(Gtk.Box):
    def __init__(self, name: str, thumb: str | None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.set_halign(Gtk.Align.CENTER)
        self.add_css_class('wp-card')
        self.name = name

        if thumb and os.path.exists(thumb):
            pic = Gtk.Picture.new_for_filename(thumb)
            pic.set_content_fit(Gtk.ContentFit.COVER)
            pic.set_can_shrink(True)
        else:
            pic = Gtk.Image.new_from_icon_name('system-lock-screen-symbolic')
            pic.set_pixel_size(48)
        pic.set_size_request(200, 120)

        frame = Gtk.Frame()
        frame.add_css_class('wp-frame')
        frame.set_child(pic)
        self.append(frame)

        lbl = Gtk.Label(label=name)
        lbl.add_css_class('lock-name')
        lbl.set_halign(Gtk.Align.CENTER)
        self.append(lbl)


# ── Page ──────────────────────────────────────────────────────────────────────

class LockscreenPage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._updating_power = False
        self._build_ui()
        self._load_power_profile()
        self._load_idle_settings()
        self._reload()

    # ── Build ─────────────────────────────────────────────────────────────────

    def _build_ui(self):
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        main.set_margin_bottom(16)

        main.append(self._build_power_section())
        main.append(self._build_idle_section())
        main.append(self._build_theme_section())

        scroll.set_child(main)
        self.append(scroll)

        bar = Gtk.ActionBar()
        self._spinner = Gtk.Spinner()
        bar.pack_start(self._spinner)
        self._status = Gtk.Label(label='')
        self._status.add_css_class('caption')
        bar.pack_start(self._status)

        btn_refresh = Gtk.Button(label='Refresh')
        btn_refresh.add_css_class('flat')
        btn_refresh.connect('clicked', lambda _: self._reload())
        bar.pack_end(btn_refresh)

        btn_apply = Gtk.Button(label='Apply Settings')
        btn_apply.add_css_class('suggested-action')
        btn_apply.connect('clicked', self._on_apply_all)
        bar.pack_end(btn_apply)

        self.append(bar)

    def _build_power_section(self) -> Gtk.Widget:
        grp = Adw.PreferencesGroup()
        grp.set_title('Power Mode')
        grp.set_margin_top(16)
        grp.set_margin_start(16)
        grp.set_margin_end(16)

        btn_box = Gtk.Box(spacing=0, margin_top=4, margin_bottom=8)
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

        grp.add(btn_box)
        return grp

    def _build_idle_section(self) -> Gtk.Widget:
        grp = Adw.PreferencesGroup()
        grp.set_title('Idle Settings')
        grp.set_description('Minutes of inactivity before the screen locks or the system suspends.')
        grp.set_margin_top(16)
        grp.set_margin_start(16)
        grp.set_margin_end(16)

        lock_row = Adw.ActionRow()
        lock_row.set_title('Screen Lock')
        lock_row.set_subtitle('Minutes until the screen locks')
        self._spin_lock = Gtk.SpinButton(
            adjustment=Gtk.Adjustment(value=7, lower=1, upper=120,
                                      step_increment=1, page_increment=5),
            numeric=True, digits=0)
        self._spin_lock.set_valign(Gtk.Align.CENTER)
        self._spin_lock.set_size_request(80, -1)
        lock_row.add_suffix(self._spin_lock)
        grp.add(lock_row)

        susp_row = Adw.ActionRow()
        susp_row.set_title('Suspend')
        susp_row.set_subtitle('Minutes until the system suspends')
        self._spin_suspend = Gtk.SpinButton(
            adjustment=Gtk.Adjustment(value=20, lower=1, upper=300,
                                      step_increment=1, page_increment=5),
            numeric=True, digits=0)
        self._spin_suspend.set_valign(Gtk.Align.CENTER)
        self._spin_suspend.set_size_request(80, -1)
        susp_row.add_suffix(self._spin_suspend)
        grp.add(susp_row)

        return grp

    def _build_theme_section(self) -> Gtk.Widget:
        grp = Adw.PreferencesGroup()
        grp.set_title('Lockscreen Theme')
        grp.set_margin_top(16)
        grp.set_margin_start(16)
        grp.set_margin_end(16)

        self._flow = Gtk.FlowBox()
        self._flow.set_valign(Gtk.Align.START)
        self._flow.set_max_children_per_line(4)
        self._flow.set_min_children_per_line(1)
        self._flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._flow.set_row_spacing(12)
        self._flow.set_column_spacing(12)
        self._flow.set_margin_top(8)
        self._flow.set_margin_bottom(4)

        grp.add(self._flow)
        return grp

    # ── Power mode ────────────────────────────────────────────────────────────

    def _load_power_profile(self):
        def _work():
            profile = _read_power_profile()
            GLib.idle_add(self._apply_power_ui, profile)
        threading.Thread(target=_work, daemon=True).start()

    def _apply_power_ui(self, profile: str):
        self._updating_power = True
        for key, btn in self._power_btns.items():
            btn.set_active(key == profile)
        self._updating_power = False
        return False

    def _on_power_toggled(self, btn, key: str):
        if not btn.get_active() or self._updating_power:
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
                target=lambda: subprocess.run(['bash', POWERMODE_SH, flag], capture_output=True),
                daemon=True,
            ).start()
        self._status.set_text(f'Power mode: {key}')

    # ── Idle settings ─────────────────────────────────────────────────────────

    def _load_idle_settings(self):
        lock, suspend = _read_hypridle()
        self._spin_lock.set_value(round(lock / 60))
        self._spin_suspend.set_value(round(suspend / 60))

    # ── Apply all ─────────────────────────────────────────────────────────────

    def _on_apply_all(self, _):
        lock_secs    = int(self._spin_lock.get_value())    * 60
        suspend_secs = int(self._spin_suspend.get_value()) * 60

        selected = self._flow.get_selected_children()
        theme_name = None
        theme_file = None
        if selected:
            card = selected[0].get_child()
            if isinstance(card, ThemeCard):
                theme_name = card.name
                theme_file = os.path.join(HYPRLOCK_THEMES, f'{theme_name}.conf')
                if not os.path.exists(theme_file):
                    theme_file = None

        self._status.set_text('Applying…')

        def _apply():
            msgs = []
            try:
                _write_hypridle(lock_secs, suspend_secs)
                _restart_hypridle()
                msgs.append('idle settings saved')
            except Exception as e:
                msgs.append(f'idle error: {e}')
            if theme_file:
                try:
                    _apply_theme(theme_file)
                    msgs.append(f'theme "{theme_name}" applied')
                except Exception as e:
                    msgs.append(f'theme error: {e}')
            GLib.idle_add(
                lambda: self._status.set_text(', '.join(msgs).capitalize() + '.') or False)

        threading.Thread(target=_apply, daemon=True).start()

    # ── Lockscreen theme ──────────────────────────────────────────────────────

    def _reload(self):
        child = self._flow.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._flow.remove(child)
            child = nxt

        self._spinner.start()
        self._status.set_text('Loading themes…')

        def _work():
            themes = []
            if os.path.isdir(HYPRLOCK_THEMES):
                for fname in sorted(os.listdir(HYPRLOCK_THEMES)):
                    if not fname.endswith('.conf'):
                        continue
                    name = fname[:-5]
                    path = os.path.join(HYPRLOCK_THEMES, fname)
                    thumb = _ensure_thumb(path, name)
                    themes.append((name, thumb))
            GLib.idle_add(self._populate, themes)

        threading.Thread(target=_work, daemon=True).start()

    def _populate(self, themes: list):
        self._spinner.stop()
        for name, thumb in themes:
            self._flow.append(ThemeCard(name, thumb))
        n = len(themes)
        self._status.set_text(f'{n} theme{"s" if n != 1 else ""}')
        return False

