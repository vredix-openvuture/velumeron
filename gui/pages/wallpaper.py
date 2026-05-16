import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw, Gio, GLib
import os, subprocess, threading, shutil
from constants import (
    WALLPAPER_H, WALLPAPER_V, VIDEO_EXTS, SET_WP, GEN_THUMBS,
)
from models.wallpaper import (
    WallpaperEntry, scan_wallpapers, load_theme_names,
    gen_id, is_horizontal_file,
)

_THEME_NAMES: dict = {}

CARD_H = 108


def _make_pic(thumb, w, h) -> Gtk.Widget:
    if thumb and os.path.exists(thumb):
        pic = Gtk.Picture.new_for_filename(thumb)
        pic.set_content_fit(Gtk.ContentFit.COVER)
        pic.set_can_shrink(True)
    else:
        pic = Gtk.Image.new_from_icon_name('image-x-generic')
    pic.set_size_request(w, h)
    return pic


def _framed(child) -> Gtk.Frame:
    f = Gtk.Frame()
    f.add_css_class('wp-frame')
    f.set_child(child)
    return f


class WallpaperCard(Gtk.Box):
    def __init__(self, entry: WallpaperEntry, on_add_counterpart=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.set_halign(Gtk.Align.CENTER)
        self.entry = entry
        self._on_add_cb = on_add_counterpart
        self._build()

        display_name = _THEME_NAMES.get(f'wp_{entry.id}', entry.id)
        lbl = Gtk.Label(label=display_name)
        lbl.add_css_class('wp-name')
        lbl.set_max_width_chars(24)
        lbl.set_ellipsize(3)
        lbl.set_xalign(0.5)
        self.append(lbl)

        if on_add_counterpart:
            add_btn = Gtk.Button(icon_name='list-add-symbolic')
            add_btn.add_css_class('flat')
            add_btn.add_css_class('wp-add-btn')
            add_btn.set_halign(Gtk.Align.CENTER)
            add_btn.set_tooltip_text(
                'Vertikales Bild hinzufügen' if entry.hor_file and not entry.ver_file
                else 'Horizontales Bild hinzufügen')
            add_btn.connect('clicked', self._on_add_clicked)
            self.append(add_btn)

    def _build(self):
        raise NotImplementedError

    def _on_add_clicked(self, _):
        if not self.entry.hor_file:
            self._on_add_cb(self.entry, 'hor')
        else:
            self._on_add_cb(self.entry, 'ver')


class HorCard(WallpaperCard):
    W = 210

    def _build(self):
        self.prepend(_framed(_make_pic(self.entry.hor_thumb, self.W, CARD_H)))


class VerCard(WallpaperCard):
    W = 65

    def _build(self):
        self.prepend(_framed(_make_pic(self.entry.ver_thumb, self.W, CARD_H)))


class SetCard(WallpaperCard):
    TOTAL_W = 285
    HOR_W   = int(285 * 2 / 3)
    VER_W   = 285 - int(285 * 2 / 3) - 2

    def _build(self):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        row.set_size_request(self.TOTAL_W, CARD_H)
        hor = _framed(_make_pic(self.entry.hor_thumb, self.HOR_W, CARD_H))
        hor.set_size_request(self.HOR_W, CARD_H)
        ver = _framed(_make_pic(self.entry.ver_thumb, self.VER_W, CARD_H))
        ver.set_size_request(self.VER_W, CARD_H)
        row.append(hor)
        row.append(ver)
        self.prepend(row)


class WallpaperPage(Gtk.Box):

    TABS = [('set', 'Sets'), ('hor', 'Horizontal'), ('ver', 'Vertikal')]

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        inner = Adw.ViewStack()
        self._inner = inner
        self._flows: dict = {}

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
        flow.set_homogeneous(False)
        flow.set_max_children_per_line({'set': 2, 'hor': 4, 'ver': 6}[key])
        flow.set_min_children_per_line(1)
        flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        flow.set_row_spacing(12)
        flow.set_column_spacing(12)
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
            global _THEME_NAMES
            _THEME_NAMES = load_theme_names()
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
                self._flows['set'].append(SetCard(e))
                counts['set'] += 1
            if e.hor_file:
                cb = None if cat == 'set' else self._add_counterpart
                self._flows['hor'].append(HorCard(e, cb))
                counts['hor'] += 1
            if e.ver_file:
                cb = None if cat == 'set' else self._add_counterpart
                self._flows['ver'].append(VerCard(e, cb))
                counts['ver'] += 1
        self._status.set_text(
            f'{counts["set"]} Sets · {counts["hor"]} Horizontal · {counts["ver"]} Vertikal')
        return False

    def _on_activated(self, child, tab_key: str):
        card = child.get_child()
        if not isinstance(card, WallpaperCard):
            return
        e = card.entry
        self._spinner.start()
        self._status.set_text(f'Setze {e.id} …')

        def _apply():
            cmd = ['bash', SET_WP]
            if tab_key in ('set', 'hor') and e.hor_file:
                cmd += ['--hor', e.hor_file]
            if tab_key in ('set', 'ver') and e.ver_file:
                cmd += ['--ver', e.ver_file]
            subprocess.run(cmd)
            GLib.idle_add(lambda: (
                self._spinner.stop(),
                self._status.set_text('Wallpaper gesetzt.')
            ) and False)

        threading.Thread(target=_apply, daemon=True).start()

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
            paths = [files.get_item(i).get_path() for i in range(files.get_n_items())]
        except Exception:
            return
        if paths:
            threading.Thread(target=self._import, args=(paths,), daemon=True).start()

    def _import(self, paths: list):
        os.makedirs(WALLPAPER_H, exist_ok=True)
        os.makedirs(WALLPAPER_V, exist_ok=True)
        info = [(p, is_horizontal_file(p), os.path.splitext(p)[1].lower() in VIDEO_EXTS)
                for p in paths]
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
