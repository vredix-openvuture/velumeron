import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
gi.require_version('GdkPixbuf', '2.0')

from gi.repository import Gtk, Adw, Gdk, GdkPixbuf, Gio, GLib
import os, re, subprocess, threading, shutil, json

def _clean_env() -> dict:
    env = dict(os.environ)
    env.pop('LD_PRELOAD', None)
    return env
from constants import (
    WALLPAPER_H, WALLPAPER_V, VIDEO_EXTS, ALL_EXTS, SET_WP, GEN_THUMBS,
    wallpaper_dir, GUI_SETTINGS,
    WALLPAPER_OLD, THEME_NAMES,
)
from models.wallpaper import (
    WallpaperEntry, WallpaperSet, SetImage,
    scan_wallpapers, load_theme_names, load_sets, save_sets,
    remove_file_from_sets, get_monitor_names, migrate_pairs_to_sets,
    gen_id, is_horizontal_file,
)
from pages.wallust import WallustPage

_THEME_NAMES: dict = {}
CARD_H = 160


def _make_pic(thumb, w, h) -> Gtk.Widget:
    if thumb and os.path.exists(thumb):
        try:
            _, nw, nh = GdkPixbuf.Pixbuf.get_file_info(thumb)
            if nw > 0 and nh > 0:
                # COVER: scale so the image fills w×h without distortion, then center-crop
                if nw / nh < w / h:
                    pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(thumb, w, -1, True)
                else:
                    pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(thumb, -1, h, True)
                sw, sh = pb.get_width(), pb.get_height()
                cx = max(0, (sw - w) // 2)
                cy = max(0, (sh - h) // 2)
                pb = pb.new_subpixbuf(cx, cy, min(w, sw), min(h, sh))
            else:
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(thumb, w, h, False)
            tex = Gdk.Texture.new_for_pixbuf(pb)
            pic = Gtk.Picture.new_for_paintable(tex)
            pic.set_content_fit(Gtk.ContentFit.FILL)
        except Exception:
            pic = Gtk.Image.new_from_icon_name('image-x-generic')
    else:
        pic = Gtk.Image.new_from_icon_name('image-x-generic')
    pic.set_size_request(w, h)
    return pic


def _framed(child) -> Gtk.Frame:
    f = Gtk.Frame()
    f.add_css_class('wp-frame')
    f.set_child(child)
    return f


def _write_alias(wp_key: str, name: str) -> None:
    lines = []
    found = False
    try:
        with open(THEME_NAMES) as fh:
            for line in fh:
                m = re.match(r'^(wp_[a-zA-Z0-9]+)\s*=', line)
                if m and m.group(1) == wp_key:
                    found = True
                    if name:
                        lines.append(f'{wp_key} = "{name}"\n')
                else:
                    lines.append(line)
    except FileNotFoundError:
        pass
    if not found and name:
        lines.append(f'{wp_key} = "{name}"\n')
    os.makedirs(os.path.dirname(THEME_NAMES), exist_ok=True)
    with open(THEME_NAMES, 'w') as fh:
        fh.writelines(lines)


# ── Pool cards (Horizontal / Vertical) ────────────────────────────────────────

def _clean_name(wp_id: str) -> str:
    """Custom-folder files carry a synthetic 'h:'/'v:' id — show the bare name."""
    return wp_id.split(':', 1)[1] if wp_id[:2] in ('h:', 'v:') else wp_id


class WallpaperCard(Gtk.Box):
    """Base for single-orientation pool cards."""

    def __init__(self, entry: WallpaperEntry, on_change=None, on_alias=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.set_halign(Gtk.Align.CENTER)
        self.add_css_class('wp-card')
        self.entry = entry
        self._on_change = on_change
        self._on_alias = on_alias
        self._build()

        display_name = _THEME_NAMES.get(f'wp_{entry.id}', _clean_name(entry.id))
        lbl = Gtk.Label(label=display_name)
        lbl.add_css_class('wp-name')
        lbl.set_max_width_chars(24)
        lbl.set_ellipsize(3)
        lbl.set_xalign(0.5)
        self._name_label = lbl
        self.append(lbl)

        gesture = Gtk.GestureClick(button=3)
        gesture.connect('pressed', self._on_right_click)
        self.add_controller(gesture)

    def _build(self):
        raise NotImplementedError

    @property
    def _file_to_move(self):
        raise NotImplementedError

    def _on_right_click(self, gesture, n_press, x, y):
        popover = Gtk.Popover()
        popover.set_has_arrow(False)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.add_css_class('ctx-menu')

        for label, action in [
            ('Add Alias',  self._show_alias_dialog),
            ('Add to Set', self._add_to_set),
        ]:
            btn = Gtk.Button(label=label)
            btn.add_css_class('flat')
            btn.set_halign(Gtk.Align.FILL)
            btn.connect('clicked', lambda _, a=action: (popover.popdown(), a()))
            box.append(btn)

        rm = Gtk.Button(label='Remove')
        rm.add_css_class('flat')
        rm.add_css_class('destructive-action')
        rm.set_halign(Gtk.Align.FILL)
        rm.connect('clicked', lambda _: (popover.popdown(), self._confirm_remove()))
        box.append(rm)

        popover.set_child(box)
        popover.set_parent(self)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(x), int(y), 1, 1
        popover.set_pointing_to(rect)
        popover.popup()

    def _show_alias_dialog(self):
        # Routed to the page so the rename happens in-panel (a separate dialog
        # window can't be used under the fullscreen layer-shell panel).
        if self._on_alias is not None:
            self._on_alias(self.entry)

    def _add_to_set(self):
        f = self._file_to_move
        if not f:
            return
        fname = os.path.basename(f)
        sets = load_sets()
        set_ids = list(sets.keys())

        combo = Gtk.ComboBoxText()
        for sid in set_ids:
            combo.append_text(sets[sid].name)
        combo.append_text('+ New Set')
        combo.set_active(0)

        wrapper = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        wrapper.set_margin_top(8)
        wrapper.set_margin_bottom(4)
        wrapper.append(combo)

        dlg = Adw.AlertDialog(heading='Add to Set', body=f'Add "{fname}" to:')
        dlg.set_extra_child(wrapper)
        dlg.add_response('cancel', 'Cancel')
        dlg.add_response('add', 'Add')
        dlg.set_default_response('add')
        dlg.set_close_response('cancel')
        dlg.set_response_appearance('add', Adw.ResponseAppearance.SUGGESTED)
        dlg.connect('response',
                    lambda d, r: self._on_add_to_set(r, combo, set_ids, sets, fname))
        dlg.present(self.get_root())

    def _on_add_to_set(self, response, combo, set_ids, sets, fname):
        if response != 'add':
            return
        active = combo.get_active()
        if active < 0:
            return
        img = SetImage(file=fname, monitor=None)
        if active >= len(set_ids):
            nid = gen_id()
            while nid in sets:
                nid = gen_id()
            sets[nid] = WallpaperSet(
                set_id=nid,
                name=os.path.splitext(fname)[0],
                images=[img],
            )
        else:
            sets[set_ids[active]].images.append(img)
        save_sets(sets)
        if self._on_change:
            self._on_change()

    def _confirm_remove(self):
        fname = os.path.basename(self._file_to_move or '')
        dlg = Adw.AlertDialog(heading='Remove Wallpaper',
                              body=f'Move {fname} to old_wallpaper?')
        dlg.add_response('cancel', 'Cancel')
        dlg.add_response('remove', 'Remove')
        dlg.set_default_response('cancel')
        dlg.set_close_response('cancel')
        dlg.set_response_appearance('remove', Adw.ResponseAppearance.DESTRUCTIVE)
        dlg.connect('response', lambda d, r: self._on_remove_response(r))
        dlg.present(self.get_root())

    def _on_remove_response(self, response):
        if response != 'remove':
            return
        f = self._file_to_move
        if f and os.path.exists(f):
            remove_file_from_sets(os.path.basename(f))
            os.makedirs(WALLPAPER_OLD, exist_ok=True)
            shutil.move(f, WALLPAPER_OLD)
        if self._on_change:
            self._on_change()


class HorCard(WallpaperCard):
    W = 300

    def _build(self):
        self.prepend(_framed(_make_pic(self.entry.hor_thumb, self.W, CARD_H)))

    @property
    def _file_to_move(self):
        return self.entry.hor_file


class VerCard(WallpaperCard):
    W = 95

    def _build(self):
        self.prepend(_framed(_make_pic(self.entry.ver_thumb, self.W, CARD_H)))

    @property
    def _file_to_move(self):
        return self.entry.ver_file


# ── Set card ──────────────────────────────────────────────────────────────────

class NewSetCard(Gtk.Box):
    TOTAL_W = 400
    HOR_W   = int(400 * 2 / 3)
    VER_W   = 400 - int(400 * 2 / 3) - 2

    def __init__(self, ws: WallpaperSet, on_change=None, on_edit=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.set_halign(Gtk.Align.CENTER)
        self.add_css_class('wp-card')
        self.ws = ws
        self._on_change = on_change
        self._on_edit = on_edit
        self._build()

        self._name_label = Gtk.Label(label=ws.name)
        self._name_label.add_css_class('wp-name')
        self._name_label.set_max_width_chars(24)
        self._name_label.set_ellipsize(3)
        self._name_label.set_xalign(0.5)
        self.append(self._name_label)

        gesture = Gtk.GestureClick(button=3)
        gesture.connect('pressed', self._on_right_click)
        self.add_controller(gesture)

    def _build(self):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        row.set_size_request(self.TOTAL_W, CARD_H)

        hor_img = next((img for img in self.ws.images if img.orientation == 'hor'), None)
        ver_img = next((img for img in self.ws.images if img.orientation == 'ver'), None)

        if hor_img and ver_img:
            hf = _framed(_make_pic(hor_img.thumb_path(), self.HOR_W, CARD_H))
            hf.set_size_request(self.HOR_W, CARD_H)
            vf = _framed(_make_pic(ver_img.thumb_path(), self.VER_W, CARD_H))
            vf.set_size_request(self.VER_W, CARD_H)
            row.append(hf)
            row.append(vf)
        elif hor_img:
            hf = _framed(_make_pic(hor_img.thumb_path(), self.TOTAL_W, CARD_H))
            hf.set_size_request(self.TOTAL_W, CARD_H)
            row.append(hf)
        elif ver_img:
            vf = _framed(_make_pic(ver_img.thumb_path(), self.VER_W, CARD_H))
            vf.set_size_request(self.VER_W, CARD_H)
            row.append(vf)
        else:
            ph = Gtk.Image.new_from_icon_name('image-x-generic')
            ph.set_size_request(self.TOTAL_W, CARD_H)
            row.append(_framed(ph))

        self.prepend(row)

    def _on_right_click(self, gesture, n_press, x, y):
        popover = Gtk.Popover()
        popover.set_has_arrow(False)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.add_css_class('ctx-menu')

        for label, action in [
            ('Edit Set', self._edit_set),
            ('Rename',   self._rename_set),
        ]:
            btn = Gtk.Button(label=label)
            btn.add_css_class('flat')
            btn.set_halign(Gtk.Align.FILL)
            btn.connect('clicked', lambda _, a=action: (popover.popdown(), a()))
            box.append(btn)

        rm = Gtk.Button(label='Remove Set')
        rm.add_css_class('flat')
        rm.add_css_class('destructive-action')
        rm.set_halign(Gtk.Align.FILL)
        rm.connect('clicked', lambda _: (popover.popdown(), self._confirm_remove()))
        box.append(rm)

        popover.set_child(box)
        popover.set_parent(self)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(x), int(y), 1, 1
        popover.set_pointing_to(rect)
        popover.popup()

    def _edit_set(self):
        if self._on_edit is not None:
            self._on_edit(self.ws)

    def _rename_set(self):
        entry_w = Gtk.Entry()
        entry_w.set_text(self.ws.name)
        entry_w.set_activates_default(True)
        entry_w.set_margin_top(8)
        entry_w.set_margin_bottom(4)

        dlg = Adw.AlertDialog(heading='Rename Set', body='')
        dlg.set_extra_child(entry_w)
        dlg.add_response('cancel', 'Cancel')
        dlg.add_response('save', 'Save')
        dlg.set_default_response('save')
        dlg.set_close_response('cancel')
        dlg.set_response_appearance('save', Adw.ResponseAppearance.SUGGESTED)
        dlg.connect('response', lambda d, r: self._on_rename(r, entry_w.get_text()))
        dlg.present(self.get_root())

    def _on_rename(self, response, name):
        name = name.strip()
        if response != 'save' or not name:
            return
        sets = load_sets()
        if self.ws.set_id in sets:
            sets[self.ws.set_id].name = name
            save_sets(sets)
        self.ws.name = name
        self._name_label.set_text(name)

    def _confirm_remove(self):
        dlg = Adw.AlertDialog(
            heading='Remove Set',
            body=f'Remove "{self.ws.name}"? Images stay in the pool.',
        )
        dlg.add_response('cancel', 'Cancel')
        dlg.add_response('remove', 'Remove')
        dlg.set_default_response('cancel')
        dlg.set_close_response('cancel')
        dlg.set_response_appearance('remove', Adw.ResponseAppearance.DESTRUCTIVE)
        dlg.connect('response', lambda d, r: self._on_remove(r))
        dlg.present(self.get_root())

    def _on_remove(self, response):
        if response != 'remove':
            return
        sets = load_sets()
        sets.pop(self.ws.set_id, None)
        save_sets(sets)
        if self._on_change:
            self._on_change()


# ── Set editor dialog ─────────────────────────────────────────────────────────

class SetEditorDialog(Adw.Window):
    def __init__(self, ws: WallpaperSet, parent=None, on_saved=None):
        super().__init__()
        self.ws = ws
        self._on_saved = on_saved
        self._panel = parent   # the layer-shell settings panel, hidden while open
        self._monitors = get_monitor_names()
        self.set_title(f'Edit Set — {ws.name}')
        self.set_default_size(520, 460)
        # Do NOT make this transient/modal against the panel: it is a fullscreen
        # TOP layer-shell window, so this dialog would render under it and the
        # panel's overlay would swallow all input ("the window can't be used").
        # Instead hide the panel while we're open and restore it on close.
        if self._panel is not None:
            self._panel.set_visible(False)
        self.connect('close-request', self._on_close)
        self._build()

    def _on_close(self, *_):
        if self._panel is not None:
            self._panel.set_visible(True)
        return False  # allow the window to close

    def _build(self):
        self._name_entry = Gtk.Entry()
        self._name_entry.set_text(self.ws.name)
        self._name_entry.set_hexpand(True)

        name_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        name_box.set_margin_start(12)
        name_box.set_margin_end(12)
        name_box.set_margin_top(12)
        name_box.set_margin_bottom(8)
        name_lbl = Gtk.Label(label='Name')
        name_lbl.set_xalign(0)
        name_box.append(name_lbl)
        name_box.append(self._name_entry)

        self._image_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self._image_box.set_margin_start(12)
        self._image_box.set_margin_end(12)
        for img in self.ws.images:
            self._image_box.append(self._make_image_row(img))

        add_hor = Gtk.Button(label='+ Horizontal')
        add_hor.add_css_class('flat')
        add_hor.connect('clicked', lambda _: self._pick_image('hor'))

        add_ver = Gtk.Button(label='+ Vertical')
        add_ver.add_css_class('flat')
        add_ver.connect('clicked', lambda _: self._pick_image('ver'))

        add_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        add_row.set_halign(Gtk.Align.CENTER)
        add_row.set_margin_top(8)
        add_row.set_margin_bottom(8)
        add_row.append(add_hor)
        add_row.append(add_ver)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content.append(name_box)
        content.append(self._image_box)
        content.append(add_row)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(content)

        cancel_btn = Gtk.Button(label='Cancel')
        cancel_btn.connect('clicked', lambda _: self.close())

        save_btn = Gtk.Button(label='Save')
        save_btn.add_css_class('suggested-action')
        save_btn.connect('clicked', lambda _: self._save())

        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_row.set_halign(Gtk.Align.END)
        btn_row.set_margin_start(12)
        btn_row.set_margin_end(12)
        btn_row.set_margin_top(8)
        btn_row.set_margin_bottom(12)
        btn_row.append(cancel_btn)
        btn_row.append(save_btn)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        root.append(scroll)
        root.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))
        root.append(btn_row)
        self.set_content(root)

    def _make_image_row(self, img: SetImage) -> Gtk.Box:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_margin_top(2)
        row.set_margin_bottom(2)
        row._img = img

        pic = _make_pic(img.thumb_path(), 80, 45)
        pic.set_valign(Gtk.Align.CENTER)
        row.append(pic)

        lbl = Gtk.Label(label=img.file)
        lbl.set_hexpand(True)
        lbl.set_xalign(0)
        lbl.set_ellipsize(3)
        row.append(lbl)

        combo = Gtk.ComboBoxText()
        combo.append_text('Auto')
        for mon in self._monitors:
            combo.append_text(mon)
        idx = 0
        if img.monitor and img.monitor in self._monitors:
            idx = self._monitors.index(img.monitor) + 1
        combo.set_active(idx)
        combo.set_valign(Gtk.Align.CENTER)
        row._monitor_combo = combo
        row.append(combo)

        rm = Gtk.Button(icon_name='list-remove-symbolic')
        rm.add_css_class('flat')
        rm.set_valign(Gtk.Align.CENTER)
        rm.connect('clicked', lambda _, r=row: self._image_box.remove(r))
        row.append(rm)

        return row

    def _pick_image(self, orientation: str):
        label = 'Horizontal' if orientation == 'hor' else 'Vertical'
        d = Gtk.FileDialog(title=f'Pick {label} Image')
        flt = Gtk.FileFilter()
        flt.set_name('Images & Videos')
        for p in ['*.jpg', '*.jpeg', '*.png', '*.webp', '*.mp4', '*.webm', '*.mkv']:
            flt.add_pattern(p)
        sl = Gio.ListStore.new(Gtk.FileFilter)
        sl.append(flt)
        d.set_filters(sl)
        base = WALLPAPER_H if orientation == 'hor' else WALLPAPER_V
        try:
            d.set_initial_folder(Gio.File.new_for_path(base))
        except Exception:
            pass
        d.open(self, None, self._image_picked)

    def _image_picked(self, dialog, result):
        try:
            f = dialog.open_finish(result)
            if not f:
                return
            fname = os.path.basename(f.get_path())
            self._image_box.append(self._make_image_row(SetImage(file=fname, monitor=None)))
        except Exception:
            pass

    def _save(self):
        name = self._name_entry.get_text().strip() or self.ws.name
        images = []
        row = self._image_box.get_first_child()
        while row:
            if hasattr(row, '_img') and hasattr(row, '_monitor_combo'):
                active = row._monitor_combo.get_active()
                monitor = (self._monitors[active - 1]
                           if 0 < active <= len(self._monitors) else None)
                images.append(SetImage(file=row._img.file, monitor=monitor))
            row = row.get_next_sibling()

        sets = load_sets()
        if self.ws.set_id in sets:
            sets[self.ws.set_id].name = name
            sets[self.ws.set_id].images = images
        else:
            sets[self.ws.set_id] = WallpaperSet(
                set_id=self.ws.set_id, name=name, images=images)
        save_sets(sets)

        if self._on_saved:
            self._on_saved()
        self.close()


# ── Page ──────────────────────────────────────────────────────────────────────

class WallpaperPage(Gtk.Box):
    TABS = [('set', 'Sets'), ('hor', 'Horizontal'), ('ver', 'Vertical')]

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        inner = Adw.ViewStack()
        self._inner = inner
        self._flows: dict = {}
        self._apply_cb = None
        self._monitors = get_monitor_names()

        # Sets are only for multi-monitor fixed combos; Vertical only when a
        # vertical monitor exists. Order: Horizontal, Vertical, Sets, Colors.
        mcount, has_vertical = self._detect_monitors()
        self._has_sets = mcount > 1
        tabs = [('hor', 'Horizontal', 'object-flip-horizontal-symbolic')]
        if has_vertical:
            tabs.append(('ver', 'Vertical', 'object-flip-vertical-symbolic'))
        if self._has_sets:
            tabs.append(('set', 'Sets', 'view-grid-symbolic'))
        self._filter = {k: 'all' for k, _, _ in tabs}

        for key, label, icon in tabs:
            inner.add_titled(self._make_tab(key), key, label).set_icon_name(icon)
        inner.add_titled(WallustPage(), 'colors', 'Colors').set_icon_name('color-select-symbolic')
        inner.set_hexpand(True)
        inner.set_vexpand(True)

        # Vertical switcher on the right (frees up the crowded bottom bar).
        switcher = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        switcher.add_css_class('wp-switcher')
        switcher.set_valign(Gtk.Align.START)
        self._switch_btns = {}
        self._switch_updating = False
        for key, label, icon in tabs + [('colors', 'Colors', 'color-select-symbolic')]:
            b = Gtk.ToggleButton()
            b.add_css_class('flat')
            b.add_css_class('wp-switch-btn')
            bx = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            img = Gtk.Image.new_from_icon_name(icon)
            img.set_pixel_size(18)
            bx.append(img)
            lb = Gtk.Label(label=label)
            lb.add_css_class('caption')
            bx.append(lb)
            b.set_child(bx)
            b.connect('toggled', self._on_switch_toggled, key)
            switcher.append(b)
            self._switch_btns[key] = b
        inner.connect('notify::visible-child-name', self._sync_switcher)
        self._switch_btns[tabs[0][0]].set_active(True)

        content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        content.set_vexpand(True)
        content.append(inner)
        content.append(switcher)

        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        main.set_vexpand(True)
        main.append(content)

        bar = Gtk.ActionBar()
        self._spinner = Gtk.Spinner()
        bar.pack_start(self._spinner)
        self._status = Gtk.Label(label='')
        self._status.add_css_class('caption')
        bar.pack_start(self._status)

        btn_refresh = Gtk.Button(label='Refresh')
        btn_refresh.connect('clicked', lambda _: self._reload())
        bar.pack_end(btn_refresh)

        if self._has_sets:
            btn_new_set = Gtk.Button(label='New Set')
            btn_new_set.connect('clicked', lambda _: self._on_new_set())
            bar.pack_end(btn_new_set)

        btn_folders = Gtk.Button(label='Folders')
        btn_folders.connect('clicked', lambda _: self._open_folders())
        bar.pack_end(btn_folders)

        btn_add = Gtk.Button(label='Add …')
        btn_add.add_css_class('suggested-action')
        btn_add.connect('clicked', self._on_add)
        bar.pack_end(btn_add)

        main.append(bar)

        self._pstack = Gtk.Stack()
        self._pstack.set_vexpand(True)
        self._pstack.add_named(main, 'main')
        self.append(self._pstack)
        self._reload()

    @staticmethod
    def _detect_monitors():
        try:
            mons = json.loads(subprocess.run(
                ['hyprctl', 'monitors', '-j'], capture_output=True, text=True).stdout)
        except Exception:
            mons = []
        count = len(mons)
        vert = any((m.get('transform') in (1, 3, 5, 7))
                   or (m.get('height', 0) > m.get('width', 0)) for m in mons)
        return count, vert

    def _on_switch_toggled(self, btn, key):
        if self._switch_updating:
            return
        if btn.get_active():
            self._switch_updating = True
            for k, b in self._switch_btns.items():
                if k != key:
                    b.set_active(False)
            self._switch_updating = False
            self._inner.set_visible_child_name(key)
        elif not any(b.get_active() for b in self._switch_btns.values()):
            btn.set_active(True)

    def _sync_switcher(self, *_):
        name = self._inner.get_visible_child_name()
        if name in self._switch_btns:
            self._switch_updating = True
            for k, b in self._switch_btns.items():
                b.set_active(k == name)
            self._switch_updating = False

    # ── In-panel set editor ─────────────────────────────────────────────────

    def open_set_editor(self, ws: WallpaperSet):
        """Show the set editor as an in-panel view (no separate window)."""
        self._editor_ws = ws
        self._monitors = get_monitor_names()

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                         margin_start=12, margin_end=12, margin_top=10, margin_bottom=6)
        back = Gtk.Button(icon_name='go-previous-symbolic')
        back.add_css_class('flat')
        back.connect('clicked', lambda _: self._close_set_editor())
        header.append(back)
        title = Gtk.Label(label='Edit Set')
        title.add_css_class('title-4')
        header.append(title)

        name_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                           margin_start=12, margin_end=12, margin_bottom=8)
        name_lbl = Gtk.Label(label='Name'); name_lbl.set_xalign(0)
        self._editor_name = Gtk.Entry()
        self._editor_name.set_text(ws.name)
        self._editor_name.set_hexpand(True)
        name_box.append(name_lbl); name_box.append(self._editor_name)

        self._editor_img_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6,
                                       margin_start=12, margin_end=12)
        for img in ws.images:
            self._editor_img_box.append(self._editor_make_row(img))

        add_img = Gtk.Button(label='Add Image')
        add_img.add_css_class('flat')
        add_img.set_halign(Gtk.Align.CENTER)
        add_img.set_margin_top(8); add_img.set_margin_bottom(8)
        add_img.connect('clicked', lambda _: self._show_set_picker())

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content.append(name_box)
        content.append(self._editor_img_box)
        content.append(add_img)
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(content)

        cancel = Gtk.Button(label='Cancel')
        cancel.connect('clicked', lambda _: self._close_set_editor())
        save = Gtk.Button(label='Save')
        save.add_css_class('suggested-action')
        save.connect('clicked', lambda _: self._save_set_editor())
        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                          margin_start=12, margin_end=12, margin_top=8, margin_bottom=12)
        btn_row.set_halign(Gtk.Align.END)
        btn_row.append(cancel); btn_row.append(save)

        editor = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        editor.append(header)
        editor.append(scroll)
        editor.append(Gtk.Separator())
        editor.append(btn_row)

        old = self._pstack.get_child_by_name('editor')
        if old is not None:
            self._pstack.remove(old)
        self._pstack.add_named(editor, 'editor')
        self._pstack.set_visible_child_name('editor')

    def _editor_make_row(self, img: SetImage) -> Gtk.Box:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                      margin_top=2, margin_bottom=2)
        row._img = img
        pic = _make_pic(img.thumb_path(), 80, 45)
        pic.set_valign(Gtk.Align.CENTER)
        row.append(pic)
        lbl = Gtk.Label(label=img.file)
        lbl.set_hexpand(True); lbl.set_xalign(0); lbl.set_ellipsize(3)
        row.append(lbl)
        combo = Gtk.ComboBoxText()
        combo.append_text('Auto')
        for mon in self._monitors:
            combo.append_text(mon)
        idx = 0
        if img.monitor and img.monitor in self._monitors:
            idx = self._monitors.index(img.monitor) + 1
        combo.set_active(idx)
        combo.set_valign(Gtk.Align.CENTER)
        row._monitor_combo = combo
        row.append(combo)
        rm = Gtk.Button(icon_name='list-remove-symbolic')
        rm.add_css_class('flat'); rm.set_valign(Gtk.Align.CENTER)
        rm.connect('clicked', lambda _, r=row: self._editor_img_box.remove(r))
        row.append(rm)
        return row

    def _show_set_picker(self):
        """In-panel picker: choose an image from the existing wallpaper library."""
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                         margin_start=12, margin_end=12, margin_top=10, margin_bottom=6)
        back = Gtk.Button(icon_name='go-previous-symbolic')
        back.add_css_class('flat')
        back.connect('clicked', lambda _: self._pstack.set_visible_child_name('editor'))
        header.append(back)
        title = Gtk.Label(label='Pick an image'); title.add_css_class('title-4')
        header.append(title)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        # Two sections so horizontal images render landscape and vertical ones
        # portrait, with a light divider between them.
        def _section(label_text, directory, w, h, per_line):
            files = []
            if os.path.isdir(directory):
                files = [f for f in sorted(os.listdir(directory))
                         if os.path.splitext(f)[1].lower() in ALL_EXTS]
            if not files:
                return None
            sec = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            lbl = Gtk.Label(label=label_text)
            lbl.set_xalign(0); lbl.add_css_class('dim-label')
            lbl.set_margin_start(14); lbl.set_margin_top(8)
            sec.append(lbl)
            flow = Gtk.FlowBox()
            flow.set_valign(Gtk.Align.START)
            flow.set_max_children_per_line(per_line)
            flow.set_min_children_per_line(1)
            flow.set_selection_mode(Gtk.SelectionMode.NONE)
            flow.set_row_spacing(12); flow.set_column_spacing(12)
            flow.set_margin_top(6); flow.set_margin_bottom(6)
            flow.set_margin_start(14); flow.set_margin_end(14)
            for fname in files:
                img = SetImage(file=fname)
                card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
                card.add_css_class('wp-card')
                card.append(_framed(_make_pic(img.thumb_path(), w, h)))
                cl = Gtk.Label(label=fname); cl.add_css_class('wp-name')
                cl.set_max_width_chars(18); cl.set_ellipsize(3)
                card.append(cl)
                btn = Gtk.Button(); btn.add_css_class('flat'); btn.set_child(card)
                btn.connect('clicked', lambda _, f=fname: self._picker_choose(f))
                flow.append(btn)
            sec.append(flow)
            return sec

        hor = _section('Horizontal', wallpaper_dir('hor'), 160, 90, 4)
        ver = _section('Vertical',   wallpaper_dir('ver'), 90, 160, 6)
        if hor is not None:
            content.append(hor)
        if hor is not None and ver is not None:
            sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
            sep.set_margin_start(14); sep.set_margin_end(14); sep.set_margin_top(6)
            content.append(sep)
        if ver is not None:
            content.append(ver)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(content)

        picker = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        picker.append(header)
        picker.append(scroll)

        old = self._pstack.get_child_by_name('editor-pick')
        if old is not None:
            self._pstack.remove(old)
        self._pstack.add_named(picker, 'editor-pick')
        self._pstack.set_visible_child_name('editor-pick')

    def _picker_choose(self, fname: str):
        self._editor_img_box.append(self._editor_make_row(SetImage(file=fname)))
        self._pstack.set_visible_child_name('editor')

    def _save_set_editor(self):
        name = self._editor_name.get_text().strip() or self._editor_ws.name
        images = []
        row = self._editor_img_box.get_first_child()
        while row:
            if hasattr(row, '_img') and hasattr(row, '_monitor_combo'):
                active = row._monitor_combo.get_active()
                monitor = (self._monitors[active - 1]
                           if 0 < active <= len(self._monitors) else None)
                images.append(SetImage(file=row._img.file, monitor=monitor))
            row = row.get_next_sibling()
        sets = load_sets()
        if self._editor_ws.set_id in sets:
            sets[self._editor_ws.set_id].name = name
            sets[self._editor_ws.set_id].images = images
        else:
            sets[self._editor_ws.set_id] = WallpaperSet(
                set_id=self._editor_ws.set_id, name=name, images=images)
        save_sets(sets)
        self._close_set_editor()
        self._reload()

    def _close_set_editor(self):
        self._pstack.set_visible_child_name('main')

    # ── Custom wallpaper folders (in-panel subpage) ───────────────────────────

    def _open_folders(self):
        try:
            with open(GUI_SETTINGS) as f:
                settings = json.load(f)
        except Exception:
            settings = {}

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                         margin_start=12, margin_end=12, margin_top=10, margin_bottom=6)
        back = Gtk.Button(icon_name='go-previous-symbolic')
        back.add_css_class('flat')
        back.connect('clicked', lambda _: self._pstack.set_visible_child_name('main'))
        header.append(back)
        title = Gtk.Label(label='Wallpaper folders'); title.add_css_class('title-4')
        header.append(title)

        group = Adw.PreferencesGroup(
            title='Custom image folders',
            description='Absolute paths to search for images. Leave empty to use '
                        'the bundled wallpapers. A custom folder is also where the '
                        '"Add …" button saves new images.')
        self._fld_hor = Adw.EntryRow(title='Horizontal folder')
        self._fld_hor.set_text(str(settings.get('wallpaper_dir_hor', '') or ''))
        bh = Gtk.Button(icon_name='folder-open-symbolic', valign=Gtk.Align.CENTER)
        bh.add_css_class('flat')
        bh.connect('clicked', lambda _: self._browse_folder(self._fld_hor))
        self._fld_hor.add_suffix(bh)
        self._fld_ver = Adw.EntryRow(title='Vertical folder')
        self._fld_ver.set_text(str(settings.get('wallpaper_dir_ver', '') or ''))
        bv = Gtk.Button(icon_name='folder-open-symbolic', valign=Gtk.Align.CENTER)
        bv.add_css_class('flat')
        bv.connect('clicked', lambda _: self._browse_folder(self._fld_ver))
        self._fld_ver.add_suffix(bv)
        group.add(self._fld_hor)
        group.add(self._fld_ver)
        page = Adw.PreferencesPage()
        page.add(group)

        save = Gtk.Button(label='Save')
        save.add_css_class('suggested-action')
        save.connect('clicked', lambda _: self._save_folders())
        cancel = Gtk.Button(label='Cancel')
        cancel.connect('clicked', lambda _: self._pstack.set_visible_child_name('main'))
        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                          margin_start=12, margin_end=12, margin_top=8, margin_bottom=12)
        btn_row.set_halign(Gtk.Align.END)
        btn_row.append(cancel); btn_row.append(save)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(header)
        box.append(page)
        box.append(btn_row)

        old = self._pstack.get_child_by_name('folders')
        if old is not None:
            self._pstack.remove(old)
        self._pstack.add_named(box, 'folders')
        self._pstack.set_visible_child_name('folders')

    def _browse_folder(self, entry):
        d = Gtk.FileDialog(title='Choose a folder')
        cur = os.path.expanduser(entry.get_text().strip())
        if cur and os.path.isdir(cur):
            try:
                d.set_initial_folder(Gio.File.new_for_path(cur))
            except Exception:
                pass
        root = self.get_root()
        if root is not None:
            root.set_visible(False)   # layer-shell: hide panel for the portal dialog
        def _done(dialog, result):
            r = self.get_root()
            try:
                f = dialog.select_folder_finish(result)
                if f:
                    entry.set_text(f.get_path())
            except Exception:
                pass
            if r is not None:
                r.set_visible(True)
        d.select_folder(None, None, _done)

    def _save_folders(self):
        try:
            with open(GUI_SETTINGS) as f:
                settings = json.load(f)
        except Exception:
            settings = {}
        settings['wallpaper_dir_hor'] = self._fld_hor.get_text().strip()
        settings['wallpaper_dir_ver'] = self._fld_ver.get_text().strip()
        try:
            os.makedirs(os.path.dirname(GUI_SETTINGS), exist_ok=True)
            with open(GUI_SETTINGS, 'w') as f:
                json.dump(settings, f, indent=2)
        except OSError:
            pass
        self._pstack.set_visible_child_name('main')
        self._reload()

    # ── In-panel rename / alias ───────────────────────────────────────────────

    def _open_alias(self, entry):
        self._alias_entry = entry
        cur = _THEME_NAMES.get(f'wp_{entry.id}', '')

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                         margin_start=12, margin_end=12, margin_top=10, margin_bottom=6)
        back = Gtk.Button(icon_name='go-previous-symbolic')
        back.add_css_class('flat')
        back.connect('clicked', lambda _: self._pstack.set_visible_child_name('main'))
        header.append(back)
        title = Gtk.Label(label='Rename'); title.add_css_class('title-4')
        header.append(title)

        group = Adw.PreferencesGroup(
            title='Display name', description=f'Alias for {_clean_name(entry.id)}')
        self._alias_field = Adw.EntryRow(title='Name')
        self._alias_field.set_text(cur)
        group.add(self._alias_field)
        page = Adw.PreferencesPage()
        page.add(group)

        save = Gtk.Button(label='Save'); save.add_css_class('suggested-action')
        save.connect('clicked', lambda _: self._save_alias())
        cancel = Gtk.Button(label='Cancel')
        cancel.connect('clicked', lambda _: self._pstack.set_visible_child_name('main'))
        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                          margin_start=12, margin_end=12, margin_top=8, margin_bottom=12)
        btn_row.set_halign(Gtk.Align.END)
        btn_row.append(cancel); btn_row.append(save)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(header); box.append(page); box.append(btn_row)
        old = self._pstack.get_child_by_name('alias')
        if old is not None:
            self._pstack.remove(old)
        self._pstack.add_named(box, 'alias')
        self._pstack.set_visible_child_name('alias')

    def _save_alias(self):
        name = self._alias_field.get_text().strip()
        key = f'wp_{self._alias_entry.id}'
        if name:
            _THEME_NAMES[key] = name
        else:
            _THEME_NAMES.pop(key, None)
        _write_alias(key, name)
        self._pstack.set_visible_child_name('main')
        self._reload()

    def set_apply_callback(self, cb):
        self._apply_cb = cb

    def _make_tab(self, key: str) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        fbar = Gtk.Box(spacing=0, margin_top=10, margin_start=14, margin_bottom=4)
        fbar.add_css_class('linked')
        btns: dict[str, Gtk.ToggleButton] = {}
        for fkey, flabel in [('all', 'All'), ('image', 'Image'), ('video', 'Video')]:
            btn = Gtk.ToggleButton(label=flabel)
            btn.connect('toggled', self._on_filter_toggled, key, fkey, btns)
            fbar.append(btn)
            btns[fkey] = btn
        flow, scroll = self._make_flow(key)
        self._flows[key] = flow
        flow.set_filter_func(self._make_filter_func(key))

        btns['all'].set_active(True)

        box.append(fbar)
        box.append(scroll)
        return box

    def _make_filter_func(self, key: str):
        def _f(child):
            f = self._filter.get(key, 'all')
            if f == 'all':
                return True
            card = child.get_child()
            if key == 'set' and isinstance(card, NewSetCard):
                is_vid = any(
                    os.path.splitext(img.file)[1].lower() in VIDEO_EXTS
                    for img in card.ws.images
                )
            elif key == 'hor' and isinstance(card, HorCard):
                fp = card.entry.hor_file
                is_vid = fp is not None and os.path.splitext(fp)[1].lower() in VIDEO_EXTS
            elif key == 'ver' and isinstance(card, VerCard):
                fp = card.entry.ver_file
                is_vid = fp is not None and os.path.splitext(fp)[1].lower() in VIDEO_EXTS
            else:
                return True
            return is_vid if f == 'video' else not is_vid
        return _f

    def _on_filter_toggled(self, btn, tab_key: str, filter_key: str, btns: dict):
        if not btn.get_active():
            if all(not b.get_active() for b in btns.values()):
                btn.set_active(True)
            return
        self._filter[tab_key] = filter_key
        for fk, b in btns.items():
            if fk != filter_key and b.get_active():
                b.set_active(False)
        self._flows[tab_key].invalidate_filter()

    def _make_flow(self, key: str):
        flow = Gtk.FlowBox()
        flow.set_valign(Gtk.Align.START)
        flow.set_homogeneous(False)
        flow.set_max_children_per_line({'set': 2, 'hor': 4, 'ver': 6}[key])
        flow.set_min_children_per_line(1)
        flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        flow.set_row_spacing(12)
        flow.set_column_spacing(12)
        flow.set_margin_top(10)
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
        self._status.set_text('Loading…')

        def _work():
            global _THEME_NAMES
            _THEME_NAMES = load_theme_names()
            migrate_pairs_to_sets()
            subprocess.run(['bash', GEN_THUMBS], capture_output=True)
            sets = load_sets()
            entries = scan_wallpapers()
            GLib.idle_add(self._populate, sets, entries)

        threading.Thread(target=_work, daemon=True).start()

    def _populate(self, sets: dict, entries: list):
        self._spinner.stop()

        if 'set' in self._flows:
            for ws in sets.values():
                self._flows['set'].append(
                    NewSetCard(ws, on_change=self._reload, on_edit=self.open_set_editor))

        hor_count = ver_count = 0
        for e in entries:
            if e.hor_file and 'hor' in self._flows:
                self._flows['hor'].append(
                    HorCard(e, on_change=self._reload, on_alias=self._open_alias))
                hor_count += 1
            if e.ver_file and 'ver' in self._flows:
                self._flows['ver'].append(
                    VerCard(e, on_change=self._reload, on_alias=self._open_alias))
                ver_count += 1

        parts = [f'{hor_count} Horizontal']
        if 'ver' in self._flows:
            parts.append(f'{ver_count} Vertical')
        if 'set' in self._flows:
            parts.insert(0, f'{len(sets)} Sets')
        self._status.set_text(' · '.join(parts))
        return False

    def _on_activated(self, child, tab_key: str):
        card = child.get_child()
        self._spinner.start()
        if self._apply_cb:
            GLib.idle_add(self._apply_cb)

        if tab_key == 'set' and isinstance(card, NewSetCard):
            sid = card.ws.set_id
            self._status.set_text(f'Applying set {card.ws.name}…')
            def _apply_set():
                subprocess.run(['bash', SET_WP, '--set', sid], env=_clean_env())
                GLib.idle_add(lambda: (self._spinner.stop(),
                    self._status.set_text('Wallpaper applied.')) and False)
            threading.Thread(target=_apply_set, daemon=False).start()

        elif tab_key == 'hor' and isinstance(card, HorCard):
            fp = card.entry.hor_file
            self._status.set_text(f'Applying {card.entry.id}…')
            def _apply_hor():
                subprocess.run(['bash', SET_WP, '--hor', fp], env=_clean_env())
                GLib.idle_add(lambda: (self._spinner.stop(),
                    self._status.set_text('Wallpaper applied.')) and False)
            threading.Thread(target=_apply_hor, daemon=False).start()

        elif tab_key == 'ver' and isinstance(card, VerCard):
            fp = card.entry.ver_file
            self._status.set_text(f'Applying {card.entry.id}…')
            def _apply_ver():
                subprocess.run(['bash', SET_WP, '--ver', fp], env=_clean_env())
                GLib.idle_add(lambda: (self._spinner.stop(),
                    self._status.set_text('Wallpaper applied.')) and False)
            threading.Thread(target=_apply_ver, daemon=False).start()

        else:
            self._spinner.stop()

    def _on_new_set(self):
        sets = load_sets()
        nid = gen_id()
        while nid in sets:
            nid = gen_id()
        ws = WallpaperSet(set_id=nid, name='New Set', images=[])
        self.open_set_editor(ws)

    def _on_add(self, _):
        d = Gtk.FileDialog(title='Add wallpaper')
        flt = Gtk.FileFilter()
        flt.set_name('Images & Videos')
        for p in ['*.jpg', '*.jpeg', '*.png', '*.webp', '*.mp4', '*.webm', '*.mkv']:
            flt.add_pattern(p)
        sl = Gio.ListStore.new(Gtk.FileFilter)
        sl.append(flt)
        d.set_filters(sl)
        # The panel is a fullscreen layer-shell window on the TOP layer; a portal
        # file dialog would render *under* it and its click would hit our
        # outside-click catcher and dismiss the panel. So hide the panel while the
        # dialog is open (parent=None — a layer-shell surface can't parent it) and
        # bring it back when the dialog returns.
        root = self.get_root()
        if root is not None:
            root.set_visible(False)
        d.open_multiple(None, None, self._files_chosen)

    def _files_chosen(self, dialog, result):
        paths = []
        try:
            files = dialog.open_multiple_finish(result)
            paths = [files.get_item(i).get_path() for i in range(files.get_n_items())]
        except Exception:
            paths = []
        root = self.get_root()
        if root is not None:
            root.set_visible(True)
        if paths:
            threading.Thread(target=self._import, args=(paths,), daemon=True).start()

    def _import(self, paths: list):
        # Copy into the effective dirs (custom path if set, else bundled). The
        # bundled dir is read-only on clients (AUR package), so adding only works
        # into a writable custom folder — surface that instead of failing silently.
        errors = 0
        for path in paths:
            is_hor = is_horizontal_file(path)
            is_vid = os.path.splitext(path)[1].lower() in VIDEO_EXTS
            try:
                self._copy_file(path, is_hor, is_vid, gen_id())
            except OSError:
                errors += 1
        if errors:
            GLib.idle_add(lambda: self._status.set_text(
                'Could not save here (read-only). Set a writable folder under "Folders".')
                or False)
        GLib.idle_add(self._reload)

    def _copy_file(self, path: str, is_hor: bool, is_vid: bool, wp_id: str):
        ext = os.path.splitext(path)[1].lower()
        if is_hor:
            stem = f'wp_{wp_id}_vid_hor' if is_vid else f'wp_{wp_id}_hor'
            dst  = os.path.join(wallpaper_dir('hor'), stem + ext)
        else:
            dst = os.path.join(wallpaper_dir('ver'), f'wp_{wp_id}_ver{ext}')
        shutil.copy2(path, dst)
