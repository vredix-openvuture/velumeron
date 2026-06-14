from __future__ import annotations
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw, GLib
import os, re, subprocess, platform

from constants import VTL, VTL_USER


# ── helpers ───────────────────────────────────────────────────────────────────

def _run(*cmd) -> str:
    try:
        return subprocess.check_output(list(cmd), stderr=subprocess.DEVNULL,
                                       text=True).strip()
    except Exception:
        return ''


def _active_theme() -> str:
    try:
        with open(os.path.join(VTL_USER, 'active-theme')) as f:
            return f.read().strip() or 'miboro'
    except Exception:
        return 'miboro'


def _vtl_version() -> str:
    try:
        tag = _run('git', '-C', VTL, 'describe', '--tags', '--abbrev=0')
        if tag:
            return tag
        sha = _run('git', '-C', VTL, 'rev-parse', '--short', 'HEAD')
        return f'dev ({sha})' if sha else 'unknown'
    except Exception:
        return 'unknown'


def _cpu_model() -> str:
    try:
        with open('/proc/cpuinfo') as f:
            for line in f:
                if line.startswith('model name'):
                    return line.split(':', 1)[1].strip()
    except Exception:
        pass
    return _run('uname', '-p') or '—'


def _ram_info() -> str:
    try:
        with open('/proc/meminfo') as f:
            data = {l.split(':')[0]: l.split(':')[1].strip()
                    for l in f if ':' in l}
        total_kb = int(data['MemTotal'].split()[0])
        avail_kb = int(data['MemAvailable'].split()[0])
        used_gb  = (total_kb - avail_kb) / 1024 / 1024
        total_gb = total_kb / 1024 / 1024
        return f'{used_gb:.1f} / {total_gb:.1f} GiB'
    except Exception:
        return '—'


def _gpu_model() -> str:
    out = _run('lspci')
    for line in out.splitlines():
        if re.search(r'VGA|3D|Display', line, re.I):
            m = re.search(r':\s*(.+?)(\[.*?\])?\s*$', line)
            if m:
                return m.group(1).strip()
    return '—'


def _disk_usage() -> str:
    try:
        st = os.statvfs('/')
        total = st.f_blocks * st.f_frsize
        free  = st.f_bfree  * st.f_frsize
        used  = total - free
        pct   = used / total * 100 if total else 0
        def _h(b: int) -> str:
            for u in ('B', 'KiB', 'MiB', 'GiB', 'TiB'):
                if b < 1024:
                    return f'{b:.1f} {u}'
                b /= 1024
            return f'{b:.1f} PiB'
        return f'{_h(used)} / {_h(total)}  ({pct:.0f} %)'
    except Exception:
        return '—'


def _uptime() -> str:
    try:
        with open('/proc/uptime') as f:
            seconds = float(f.read().split()[0])
        d = int(seconds // 86400)
        h = int((seconds % 86400) // 3600)
        m = int((seconds % 3600) // 60)
        parts = []
        if d:
            parts.append(f'{d}d')
        if h:
            parts.append(f'{h}h')
        parts.append(f'{m}m')
        return ' '.join(parts)
    except Exception:
        return '—'


def _os_name() -> str:
    try:
        with open('/etc/os-release') as f:
            for line in f:
                if line.startswith('PRETTY_NAME='):
                    return line.split('=', 1)[1].strip().strip('"')
    except Exception:
        pass
    return platform.system()


def _wm_version() -> str:
    out = _run('hyprctl', 'version')
    for line in out.splitlines():
        if 'Hyprland' in line:
            m = re.search(r'(v[\d.]+)', line)
            return m.group(1) if m else line.strip()
    return '—'


# ── InfoPage ──────────────────────────────────────────────────────────────────

class InfoPage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._stat_labels: dict[str, Gtk.Label] = {}
        self._build_ui()
        self._refresh_stats()
        GLib.timeout_add_seconds(5, self._refresh_stats)

    def _build_ui(self):
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)

        page = Adw.PreferencesPage()

        # ── Vutureland Installation ───────────────────────────────────────────
        vtl_group = Adw.PreferencesGroup(title='Vutureland Installation')

        vtl_info = [
            ('Version',     _vtl_version()),
            ('Package dir', VTL),
            ('User config', VTL_USER),
            ('Active theme', _active_theme()),
        ]
        for label, value in vtl_info:
            row = Adw.ActionRow(title=label)
            lbl = Gtk.Label(label=value)
            lbl.add_css_class('dim-label')
            lbl.set_selectable(True)
            lbl.set_ellipsize(3)  # PANGO_ELLIPSIZE_END
            lbl.set_max_width_chars(40)
            row.add_suffix(lbl)
            vtl_group.add(row)

        page.add(vtl_group)

        # ── System Stats ─────────────────────────────────────────────────────
        stats_group = Adw.PreferencesGroup(
            title='System', description='Refreshes every 5 seconds')

        stat_defs = [
            ('user',    'User',    os.environ.get('USER', os.environ.get('LOGNAME', '—'))),
            ('session', 'Session', os.environ.get('XDG_SESSION_TYPE', 'wayland')),
            ('wm',      'WM',      '—'),
            ('os',      'OS',      _os_name()),
            ('kernel',  'Kernel',  platform.release()),
            ('uptime',  'Uptime',  '—'),
            ('cpu',     'CPU',     _cpu_model()),
            ('ram',     'RAM',     '—'),
            ('gpu',     'GPU',     _gpu_model()),
            ('disk',    'Disk (/)', '—'),
        ]
        for key, title, initial in stat_defs:
            row = Adw.ActionRow(title=title)
            lbl = Gtk.Label(label=initial)
            lbl.add_css_class('dim-label')
            lbl.set_selectable(True)
            lbl.set_ellipsize(3)
            lbl.set_max_width_chars(52)
            row.add_suffix(lbl)
            stats_group.add(row)
            self._stat_labels[key] = lbl

        page.add(stats_group)
        scroll.set_child(page)
        self.append(scroll)

    def _refresh_stats(self) -> bool:
        self._stat_labels['wm'].set_label(_wm_version())
        self._stat_labels['uptime'].set_label(_uptime())
        self._stat_labels['ram'].set_label(_ram_info())
        self._stat_labels['disk'].set_label(_disk_usage())
        return True  # keep the timeout alive
