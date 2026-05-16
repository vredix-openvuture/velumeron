#!/usr/bin/env python3
"""Vutureland Settings — GTK4/Adwaita control panel"""

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw, Gdk, GLib, Gio
import os, re, json, shutil, subprocess, threading, random, string
from dataclasses import dataclass
from typing import Optional

# ── Constants ──────────────────────────────────────────────────────────────────

VTL          = os.path.expanduser("~/.config/vutureland")
WALLPAPER_H  = f"{VTL}/assets/wallpaper/horizontal"
WALLPAPER_V  = f"{VTL}/assets/wallpaper/vertical"
THUMB_DIR    = os.path.expanduser("~/.cache/vutureland/wallpaper-thumbs")
SET_WP       = f"{VTL}/assets/scripts/wallpaper-set.sh"
GEN_THUMBS   = f"{VTL}/rofi/assets/generate-thumbnail.sh"
SETUP_HYPR   = f"{VTL}/.setup/hyprland.sh"
SETUP_WAYBAR = f"{VTL}/.setup/waybar.sh"
TERMINAL     = "kitty"

VIDEO_EXTS = {'.mp4', '.webm', '.mkv', '.avi', '.mov'}
IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.webp'}
ALL_EXTS   = IMAGE_EXTS | VIDEO_EXTS

ID_RE = re.compile(r'^wp_([a-zA-Z0-9]{6})_(vid_hor|hor|ver)$')

# ── Helpers ────────────────────────────────────────────────────────────────────

def gen_id() -> str:
    return ''.join(random.choices(string.ascii_letters + string.digits, k=6))

def extract_id(stem: str) -> Optional[str]:
    m = ID_RE.match(stem)
    return m.group(1) if m else None

def get_dims(path: str):
    ext = os.path.splitext(path)[1].lower()
    try:
        if ext in VIDEO_EXTS:
            r = subprocess.run(
                ['ffprobe', '-v', 'quiet', '-print_format', 'json',
                 '-show_streams', path],
                capture_output=True, text=True)
            for s in json.loads(r.stdout).get('streams', []):
                if s.get('codec_type') == 'video':
                    return int(s['width']), int(s['height'])
        else:
            r = subprocess.run(['identify', '-format', '%w %h', path],
                               capture_output=True, text=True)
            parts = r.stdout.strip().split()
            if len(parts) >= 2:
                return int(parts[0]), int(parts[1])
    except Exception:
        pass
    return None, None

def is_horizontal_file(path: str) -> bool:
    w, h = get_dims(path)
    return (w >= h) if w else True

# ── Data model ─────────────────────────────────────────────────────────────────

@dataclass
class WallpaperEntry:
    id: str
    hor_file: Optional[str] = None
    ver_file: Optional[str] = None
    hor_thumb: Optional[str] = None
    ver_thumb: Optional[str] = None

    @property
    def category(self) -> str:
        if self.hor_file and self.ver_file:
            return 'set'
        return 'hor' if self.hor_file else 'ver'

def scan_wallpapers() -> list:
    entries: dict[str, WallpaperEntry] = {}

    def _scan(directory, is_hor):
        if not os.path.isdir(directory):
            return
        for fname in sorted(os.listdir(directory)):
            ext = os.path.splitext(fname)[1].lower()
            if ext not in ALL_EXTS:
                continue
            stem = os.path.splitext(fname)[0]
            wp_id = extract_id(stem)
            if not wp_id:
                continue
            e = entries.setdefault(wp_id, WallpaperEntry(id=wp_id))
            thumb = os.path.join(THUMB_DIR, stem + '.png')
            if is_hor:
                e.hor_file  = os.path.join(directory, fname)
                e.hor_thumb = thumb
            else:
                e.ver_file  = os.path.join(directory, fname)
                e.ver_thumb = thumb

    _scan(WALLPAPER_H, True)
    _scan(WALLPAPER_V, False)
    return sorted(entries.values(), key=lambda e: e.id)

# ── Card widgets ───────────────────────────────────────────────────────────────

CARD_H = 108  # fixed card image height

def _make_pic(thumb: Optional[str], w: int, h: int) -> Gtk.Widget:
    if thumb and os.path.exists(thumb):
        pic = Gtk.Picture.new_for_filename(thumb)
        pic.set_content_fit(Gtk.ContentFit.COVER)
        pic.set_can_shrink(True)
    else:
        pic = Gtk.Image.new_from_icon_name('image-x-generic')
    pic.set_size_request(w, h)
    return pic

def _framed(child: Gtk.Widget) -> Gtk.Frame:
    f = Gtk.Frame()
    f.add_css_class('wp-frame')
    f.set_child(child)
    return f

class WallpaperCard(Gtk.Box):
    def __init__(self, entry: WallpaperEntry, on_add_counterpart=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.entry = entry
        self._on_add_cb = on_add_counterpart
        self._build()

        lbl = Gtk.Label(label=entry.id)
        lbl.add_css_class('caption')
        lbl.set_ellipsize(3)
        self.append(lbl)

        if on_add_counterpart:
            gc = Gtk.GestureClick(button=3)
            gc.connect('pressed', self._right_click)
            self.add_controller(gc)

    def _build(self):
        raise NotImplementedError

    def _right_click(self, gesture, n, x, y):
        menu   = Gio.Menu()
        ag     = Gio.SimpleActionGroup()

        if not self.entry.hor_file:
            menu.append('Horizontales Bild hinzufügen …', 'wp.add-hor')
            a = Gio.SimpleAction.new('add-hor', None)
            a.connect('activate', lambda *_: self._on_add_cb(self.entry, 'hor'))
            ag.add_action(a)

        if not self.entry.ver_file:
            menu.append('Vertikales Bild hinzufügen …', 'wp.add-ver')
            a = Gio.SimpleAction.new('add-ver', None)
            a.connect('activate', lambda *_: self._on_add_cb(self.entry, 'ver'))
            ag.add_action(a)

        if not menu.get_n_items():
            return

        self.insert_action_group('wp', ag)
        pop = Gtk.PopoverMenu.new_from_model(menu)
        pop.set_parent(self)
        r = Gdk.Rectangle()
        r.x, r.y, r.width, r.height = int(x), int(y), 1, 1
        pop.set_pointing_to(r)
        pop.popup()


class HorCard(WallpaperCard):
    W = 210

    def _build(self):
        self.prepend(_framed(_make_pic(self.entry.hor_thumb, self.W, CARD_H)))


class VerCard(WallpaperCard):
    W = 65   # portrait ~9:16 at CARD_H=108

    def _build(self):
        self.prepend(_framed(_make_pic(self.entry.ver_thumb, self.W, CARD_H)))


class SetCard(WallpaperCard):
    TOTAL_W = 285
    HOR_W   = int(285 * 2 / 3)      # ~190
    VER_W   = 285 - int(285 * 2 / 3) - 2  # ~93

    def _build(self):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        row.set_size_request(self.TOTAL_W, CARD_H)

        hor_frame = _framed(_make_pic(self.entry.hor_thumb, self.HOR_W, CARD_H))
        hor_frame.set_size_request(self.HOR_W, CARD_H)
        row.append(hor_frame)

        ver_frame = _framed(_make_pic(self.entry.ver_thumb, self.VER_W, CARD_H))
        ver_frame.set_size_request(self.VER_W, CARD_H)
        row.append(ver_frame)

        self.prepend(row)

# ── Wallpaper page ─────────────────────────────────────────────────────────────

class WallpaperPage(Gtk.Box):

    TABS = [
        ('set', 'Sets'),
        ('hor', 'Horizontal'),
        ('ver', 'Vertikal'),
    ]

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)

        inner = Adw.ViewStack()
        self._inner = inner
        self._flows: dict[str, Gtk.FlowBox] = {}

        for key, label in self.TABS:
            flow, scroll = self._make_flow(key)
            self._flows[key] = flow
            inner.add_titled(scroll, key, label)

        switcher = Adw.ViewSwitcherBar()
        switcher.set_stack(inner)
        switcher.set_reveal(True)

        inner.set_vexpand(True)
        self.append(inner)
        self.append(switcher)

        bar = Gtk.ActionBar()
        self._spinner = Gtk.Spinner()
        bar.pack_start(self._spinner)
        self._status = Gtk.Label(label='')
        self._status.add_css_class('caption')
        bar.pack_start(self._status)

        btn_refresh = Gtk.Button(label='Aktualisieren')
        btn_refresh.connect('clicked', lambda _: self._reload())
        bar.pack_end(btn_refresh)

        btn_add = Gtk.Button(label='Hinzufügen …')
        btn_add.add_css_class('suggested-action')
        btn_add.connect('clicked', self._on_add)
        bar.pack_end(btn_add)

        self.append(bar)
        self._reload()

    def _make_flow(self, key: str):
        flow = Gtk.FlowBox()
        flow.set_valign(Gtk.Align.START)
        flow.set_max_children_per_line(4)
        flow.set_min_children_per_line(1)
        flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        flow.set_row_spacing(10)
        flow.set_column_spacing(10)
        flow.set_margin_top(14)
        flow.set_margin_bottom(14)
        flow.set_margin_start(14)
        flow.set_margin_end(14)
        flow.connect('child-activated',
                     lambda fb, child, k=key: self._on_activated(child, k))

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(flow)
        return flow, scroll

    def _clear(self):
        for flow in self._flows.values():
            child = flow.get_first_child()
            while child:
                nxt = child.get_next_sibling()
                flow.remove(child)
                child = nxt

    def _reload(self):
        self._clear()
        self._spinner.start()
        self._status.set_text('Lade …')

        def _work():
            subprocess.run(['bash', GEN_THUMBS], capture_output=True)
            entries = scan_wallpapers()
            GLib.idle_add(self._populate, entries)

        threading.Thread(target=_work, daemon=True).start()

    def _populate(self, entries: list):
        self._spinner.stop()
        counts = {'set': 0, 'hor': 0, 'ver': 0}
        for e in entries:
            cat = e.category
            if cat == 'set':
                card = SetCard(e)
            elif cat == 'hor':
                card = HorCard(e, self._add_counterpart)
            else:
                card = VerCard(e, self._add_counterpart)
            self._flows[cat].append(card)
            counts[cat] += 1

        self._status.set_text(
            f'{counts["set"]} Sets · {counts["hor"]} Horizontal · {counts["ver"]} Vertikal')
        return False

    def _on_activated(self, child, category: str):
        card = child.get_child()
        if not isinstance(card, WallpaperCard):
            return
        e = card.entry
        self._spinner.start()
        self._status.set_text(f'Setze {e.id} …')

        def _apply():
            cmd = ['bash', SET_WP]
            if e.hor_file:
                cmd += ['--hor', e.hor_file]
            if e.ver_file:
                cmd += ['--ver', e.ver_file]
            subprocess.run(cmd)
            GLib.idle_add(lambda: (
                self._spinner.stop(),
                self._status.set_text('Wallpaper gesetzt.')
            ) and False)

        threading.Thread(target=_apply, daemon=True).start()

    # ── Import: single file or pair ──────────────────────────────────────────

    def _on_add(self, _):
        d = Gtk.FileDialog(title='Wallpaper hinzufügen')
        f = Gtk.FileFilter()
        f.set_name('Bilder & Videos')
        for p in ['*.jpg', '*.jpeg', '*.png', '*.webp', '*.mp4', '*.webm', '*.mkv']:
            f.add_pattern(p)
        s = Gio.ListStore.new(Gtk.FileFilter)
        s.append(f)
        d.set_filters(s)
        d.open_multiple(self.get_root(), None, self._files_chosen)

    def _files_chosen(self, dialog, result):
        try:
            files = dialog.open_multiple_finish(result)
            paths = [files.get_item(i).get_path()
                     for i in range(files.get_n_items())]
        except Exception:
            return
        if paths:
            threading.Thread(target=self._import, args=(paths,), daemon=True).start()

    def _import(self, paths: list):
        os.makedirs(WALLPAPER_H, exist_ok=True)
        os.makedirs(WALLPAPER_V, exist_ok=True)

        info = [(p, is_horizontal_file(p),
                 os.path.splitext(p)[1].lower() in VIDEO_EXTS)
                for p in paths]

        # Exactly 2 files with different orientations → natural set
        if len(info) == 2 and info[0][1] != info[1][1]:
            wp_id = gen_id()
            for path, is_hor, is_vid in info:
                self._copy_file(path, is_hor, is_vid, wp_id)
        else:
            for path, is_hor, is_vid in info:
                self._copy_file(path, is_hor, is_vid, gen_id())

        GLib.idle_add(self._reload)

    def _copy_file(self, path: str, is_hor: bool, is_vid: bool, wp_id: str):
        ext = os.path.splitext(path)[1].lower()
        if is_hor:
            stem = f'wp_{wp_id}_vid_hor' if is_vid else f'wp_{wp_id}_hor'
            dst  = os.path.join(WALLPAPER_H, stem + ext)
        else:
            dst = os.path.join(WALLPAPER_V, f'wp_{wp_id}_ver{ext}')
        shutil.copy2(path, dst)

    # ── Add counterpart (right-click) ────────────────────────────────────────

    def _add_counterpart(self, entry: WallpaperEntry, orientation: str):
        label = 'Horizontales Bild' if orientation == 'hor' else 'Vertikales Bild'
        d = Gtk.FileDialog(title=f'{label} für {entry.id} hinzufügen')
        f = Gtk.FileFilter()
        f.set_name('Bilder & Videos')
        for p in ['*.jpg', '*.jpeg', '*.png', '*.webp', '*.mp4', '*.webm', '*.mkv']:
            f.add_pattern(p)
        s = Gio.ListStore.new(Gtk.FileFilter)
        s.append(f)
        d.set_filters(s)
        d.open(self.get_root(), None,
               lambda dlg, res, e=entry, o=orientation:
               self._counterpart_chosen(dlg, res, e, o))

    def _counterpart_chosen(self, dialog, result,
                            entry: WallpaperEntry, orientation: str):
        try:
            file = dialog.open_finish(result)
            if not file:
                return
            path = file.get_path()
            ext  = os.path.splitext(path)[1].lower()
            is_vid = ext in VIDEO_EXTS

            if orientation == 'hor':
                stem = f'wp_{entry.id}_vid_hor' if is_vid else f'wp_{entry.id}_hor'
                dst  = os.path.join(WALLPAPER_H, stem + ext)
            else:
                dst = os.path.join(WALLPAPER_V, f'wp_{entry.id}_ver{ext}')

            shutil.copy2(path, dst)
            self._reload()
        except Exception:
            pass


# ── Setup pages ────────────────────────────────────────────────────────────────

def build_setup_page(icon: str, title: str, desc: str, script: str, btn: str):
    page = Adw.StatusPage()
    page.set_icon_name(icon)
    page.set_title(title)
    page.set_description(desc)
    page.set_vexpand(True)
    b = Gtk.Button(label=btn)
    b.add_css_class('pill')
    b.add_css_class('suggested-action')
    b.connect('clicked', lambda _: subprocess.Popen([TERMINAL, '-e', script]))
    page.set_child(b)
    return page


# ── Main window ────────────────────────────────────────────────────────────────

class MainWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title('Vutureland Settings')
        self.set_default_size(1050, 720)

        stack = Adw.ViewStack()

        hypr_page = build_setup_page(
            'preferences-desktop-display-symbolic', 'Hyprland',
            'Monitore, Workspaces, Peripherals,\nAutostart und Window Rules.',
            SETUP_HYPR, 'Hyprland Setup öffnen')
        stack.add_titled_with_icon(hypr_page, 'hyprland', 'Hyprland',
                                   'preferences-desktop-display-symbolic')

        waybar_page = build_setup_page(
            'view-grid-symbolic', 'Waybar',
            'Module auswählen, anordnen\nund die Leiste neu aufbauen.',
            SETUP_WAYBAR, 'Waybar Setup öffnen')
        stack.add_titled_with_icon(waybar_page, 'waybar', 'Waybar',
                                   'view-grid-symbolic')

        wp_page = WallpaperPage()
        stack.add_titled_with_icon(wp_page, 'wallpaper', 'Wallpaper',
                                   'image-x-generic-symbolic')

        header = Adw.HeaderBar()
        switcher = Adw.ViewSwitcher()
        switcher.set_stack(stack)
        switcher.set_policy(Adw.ViewSwitcherPolicy.WIDE)
        header.set_title_widget(switcher)

        tv = Adw.ToolbarView()
        tv.add_top_bar(header)
        tv.set_content(stack)
        self.set_content(tv)


# ── CSS ────────────────────────────────────────────────────────────────────────

CSS = b"""
.wp-frame {
    border-radius: 8px;
}
flowboxchild:selected > box .wp-frame {
    outline: 3px solid @accent_color;
    outline-offset: -2px;
}
"""


# ── App ────────────────────────────────────────────────────────────────────────

class VuturelandSettings(Adw.Application):
    def __init__(self):
        super().__init__(application_id='com.vutureland.settings',
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.connect('activate', self._activate)

    def _activate(self, _):
        p = Gtk.CssProvider()
        p.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), p,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        MainWindow(application=self).present()


if __name__ == '__main__':
    VuturelandSettings().run()
