from __future__ import annotations
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw, Gdk, GLib, Pango
import subprocess

from constants import LAUNCH_WAYBAR
from models.waybar import (
    scan_bars, read_bar_slots, write_bar_slots,
    scan_modules_by_section, BarConfig,
)

_INVALID = Gtk.INVALID_LIST_POSITION


def _build_key_map(sections: list) -> dict[str, str]:
    return {key: display for _, mods in sections for key, display in mods}


class BarZone(Gtk.Box):
    """Left / center / right drop zone inside the bar preview."""

    def __init__(self, zone_id: str, label: str, on_remove, on_drop):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._zone_id = zone_id
        self._modules: list[str] = []
        self._key_map: dict[str, str] = {}
        self._on_remove = on_remove
        self._on_drop = on_drop

        self.set_vexpand(True)
        self.set_hexpand(True)
        self.add_css_class('bar-zone')

        hdr = Gtk.Label(label=label)
        hdr.add_css_class('heading')
        hdr.set_margin_bottom(4)
        self.append(hdr)

        self._chips_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self._chips_box.set_vexpand(True)
        self.append(self._chips_box)

        self._hint = Gtk.Label(label='Drop here')
        self._hint.add_css_class('dim-label')
        self._hint.add_css_class('caption')
        self.append(self._hint)

        tgt = Gtk.DropTarget.new(str, Gdk.DragAction.COPY | Gdk.DragAction.MOVE)
        tgt.connect('drop', self._on_drop_cb)
        tgt.connect('enter', self._on_enter)
        tgt.connect('leave', self._on_leave)
        self.add_controller(tgt)

    def set_data(self, modules: list[str], key_map: dict[str, str]):
        self._modules = modules
        self._key_map = key_map
        self._refresh()

    def refresh(self):
        self._refresh()

    def _refresh(self):
        child = self._chips_box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._chips_box.remove(child)
            child = nxt
        for key in self._modules:
            self._chips_box.append(self._make_chip(key))
        self._hint.set_visible(not self._modules)

    def _make_chip(self, key: str) -> Gtk.Box:
        display = self._key_map.get(key, key)
        chip = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        chip.add_css_class('module-chip')

        lbl = Gtk.Label(label=display)
        lbl.set_ellipsize(Pango.EllipsizeMode.END)
        lbl.set_max_width_chars(16)
        lbl.set_hexpand(True)
        lbl.set_halign(Gtk.Align.START)
        chip.append(lbl)

        rm = Gtk.Button(icon_name='window-close-symbolic')
        rm.add_css_class('flat')
        rm.connect('clicked', lambda _, k=key: self._on_remove(self._zone_id, k))
        chip.append(rm)

        src = Gtk.DragSource.new()
        src.set_actions(Gdk.DragAction.MOVE)
        src.connect('prepare', lambda s, x, y, k=key:
                    Gdk.ContentProvider.new_for_value(f"zone:{self._zone_id}:{k}"))
        src.connect('drag-begin', lambda s, drag:
                    s.set_icon(Gtk.WidgetPaintable.new(chip), 0, 0))
        chip.add_controller(src)

        return chip

    def _on_drop_cb(self, _tgt, value: str, x, y) -> bool:
        self.remove_css_class('bar-zone-hover')
        if value.startswith('palette:'):
            self._on_drop(None, self._zone_id, value[8:])
            return True
        if value.startswith('zone:'):
            parts = value.split(':', 2)
            if len(parts) == 3 and parts[1] != self._zone_id:
                self._on_drop(parts[1], self._zone_id, parts[2])
                return True
        return False

    def _on_enter(self, _tgt, x, y) -> Gdk.DragAction:
        self.add_css_class('bar-zone-hover')
        return Gdk.DragAction.COPY

    def _on_leave(self, _tgt):
        self.remove_css_class('bar-zone-hover')


class WaybarPage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._bars: list[BarConfig] = scan_bars()
        self._monitors: list[str] = self._collect_monitors()
        self._cur_bar: BarConfig | None = None
        self._left: list[str] = []
        self._center: list[str] = []
        self._right: list[str] = []
        self._sections_h = scan_modules_by_section('horizontal')
        self._sections_v = scan_modules_by_section('vertical')
        self._map_h = _build_key_map(self._sections_h)
        self._map_v = _build_key_map(self._sections_v)
        self._zones: dict[str, BarZone] = {}

        self._build_ui()
        self._populate_monitors()

    # ── data helpers ────────────────────────────────────────────────────────

    def _collect_monitors(self) -> list[str]:
        seen: list[str] = []
        for b in self._bars:
            if b.monitor not in seen:
                seen.append(b.monitor)
        return seen

    def _bars_for(self, monitor: str) -> list[BarConfig]:
        return [b for b in self._bars if b.monitor == monitor]

    def _active_key_map(self) -> dict[str, str]:
        return self._map_v if self._cur_bar and self._cur_bar.orientation() == 'vertical' else self._map_h

    def _active_sections(self) -> list:
        return self._sections_v if self._cur_bar and self._cur_bar.orientation() == 'vertical' else self._sections_h

    def _slot_list(self, zone_id: str) -> list[str]:
        return {'left': self._left, 'center': self._center, 'right': self._right}[zone_id]

    # ── UI construction ──────────────────────────────────────────────────────

    def _build_ui(self):
        # Selector bar
        sel = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                      margin_start=12, margin_end=12,
                      margin_top=8, margin_bottom=8)

        sel.append(Gtk.Label(label='Monitor:'))
        self._mon_combo = Gtk.DropDown.new_from_strings([])
        self._mon_combo.set_hexpand(True)
        self._mon_combo.connect('notify::selected', self._on_monitor_changed)
        sel.append(self._mon_combo)

        sel.append(Gtk.Label(label='Bar:'))
        self._bar_combo = Gtk.DropDown.new_from_strings([])
        self._bar_combo.set_hexpand(True)
        self._bar_combo.connect('notify::selected', self._on_bar_changed)
        sel.append(self._bar_combo)

        self.append(sel)
        self.append(Gtk.Separator())

        # Main split: zones (left) | palette (right)
        main = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        main.set_vexpand(True)

        # -- Zones panel --
        zones_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                               margin_start=12, margin_end=12,
                               margin_top=12, margin_bottom=12)
        zones_panel.set_size_request(360, -1)

        hdr = Gtk.Label(label='Bar Layout')
        hdr.add_css_class('title-4')
        hdr.set_halign(Gtk.Align.START)
        zones_panel.append(hdr)

        zones_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        zones_row.set_vexpand(True)
        zones_row.set_homogeneous(True)
        for zone_id, label in [('left', 'Left'), ('center', 'Center'), ('right', 'Right')]:
            z = BarZone(zone_id, label, self._on_remove, self._on_zone_drop)
            self._zones[zone_id] = z
            zones_row.append(z)
        zones_panel.append(zones_row)

        empty = Adw.StatusPage()
        empty.set_icon_name('view-grid-symbolic')
        empty.set_title('No bars configured')
        empty.set_description('Run waybar.sh to set up bars first, then reload here.')
        empty.set_vexpand(True)

        self._stack = Gtk.Stack()
        self._stack.add_named(empty, 'empty')
        self._stack.add_named(zones_panel, 'zones')
        self._stack.set_visible_child_name('empty')
        main.append(self._stack)

        main.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))

        # -- Palette panel --
        pal_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        pal_panel.set_hexpand(True)

        pal_hdr = Gtk.Label(label='Module Palette')
        pal_hdr.add_css_class('title-4')
        pal_hdr.set_halign(Gtk.Align.START)
        pal_hdr.set_margin_start(12)
        pal_hdr.set_margin_top(12)
        pal_hdr.set_margin_bottom(8)
        pal_panel.append(pal_hdr)

        sc = Gtk.ScrolledWindow()
        sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sc.set_vexpand(True)
        self._palette_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0,
                                     margin_start=12, margin_end=12, margin_bottom=12)
        sc.set_child(self._palette_box)
        pal_panel.append(sc)
        main.append(pal_panel)

        self.append(main)

        # Action bar
        action_bar = Gtk.ActionBar()
        self._status = Gtk.Label(label='')
        self._status.add_css_class('caption')
        action_bar.pack_start(self._status)

        reload_btn = Gtk.Button(label='Reload bars')
        reload_btn.add_css_class('flat')
        reload_btn.connect('clicked', self._on_reload)
        action_bar.pack_end(reload_btn)

        self._apply_btn = Gtk.Button(label='Apply & Restart Waybar')
        self._apply_btn.add_css_class('suggested-action')
        self._apply_btn.connect('clicked', self._on_apply)
        action_bar.pack_end(self._apply_btn)

        self.append(action_bar)

    # ── population ──────────────────────────────────────────────────────────

    def _populate_monitors(self):
        strings = Gtk.StringList()
        for m in self._monitors:
            strings.append(m)
        self._mon_combo.set_model(strings)

    def _on_monitor_changed(self, combo, _):
        idx = combo.get_selected()
        if idx == _INVALID or not self._monitors:
            return
        bars = self._bars_for(self._monitors[idx])
        strings = Gtk.StringList()
        for b in bars:
            strings.append(b.label)
        self._bar_combo.set_model(strings)

    def _on_bar_changed(self, combo, _):
        mon_idx = self._mon_combo.get_selected()
        bar_idx = combo.get_selected()
        if mon_idx == _INVALID or bar_idx == _INVALID or not self._monitors:
            return
        bars = self._bars_for(self._monitors[mon_idx])
        if bar_idx >= len(bars):
            return
        self._cur_bar = bars[bar_idx]
        left, center, right = read_bar_slots(self._cur_bar)
        self._left, self._center, self._right = list(left), list(center), list(right)
        self._status.set_text('')
        self._refresh_zones()
        self._refresh_palette()
        self._stack.set_visible_child_name('zones')

    # ── zone / palette refresh ───────────────────────────────────────────────

    def _refresh_zones(self):
        key_map = self._active_key_map()
        for zone_id, mods in [('left', self._left), ('center', self._center), ('right', self._right)]:
            self._zones[zone_id].set_data(mods, key_map)

    def _refresh_palette(self):
        child = self._palette_box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._palette_box.remove(child)
            child = nxt

        for section, mods in self._active_sections():
            if not mods:
                continue
            hdr = Gtk.Label(label=section)
            hdr.add_css_class('heading')
            hdr.set_halign(Gtk.Align.START)
            hdr.set_margin_top(8)
            hdr.set_margin_bottom(4)
            self._palette_box.append(hdr)

            flow = Gtk.FlowBox()
            flow.set_selection_mode(Gtk.SelectionMode.NONE)
            flow.set_column_spacing(4)
            flow.set_row_spacing(4)
            flow.set_max_children_per_line(10)
            for key, display in mods:
                flow.append(self._make_palette_chip(key, display))
            self._palette_box.append(flow)

    def _make_palette_chip(self, key: str, display: str) -> Gtk.FlowBoxChild:
        child = Gtk.FlowBoxChild()
        child.set_focusable(False)

        btn = Gtk.Button(label=display)
        btn.add_css_class('palette-chip')
        btn.set_tooltip_text(key)
        child.set_child(btn)

        src = Gtk.DragSource.new()
        src.set_actions(Gdk.DragAction.COPY)
        src.connect('prepare', lambda s, x, y, k=key:
                    Gdk.ContentProvider.new_for_value(f"palette:{k}"))
        src.connect('drag-begin', lambda s, drag:
                    s.set_icon(Gtk.WidgetPaintable.new(btn), 0, 0))
        btn.add_controller(src)

        return child

    # ── DnD / edit callbacks ─────────────────────────────────────────────────

    def _on_remove(self, zone_id: str, key: str):
        mods = self._slot_list(zone_id)
        if key in mods:
            mods.remove(key)
        self._zones[zone_id].refresh()
        self._status.set_text('Unsaved changes')

    def _on_zone_drop(self, src_zone: str | None, dst_zone: str, key: str):
        if src_zone is not None:
            src = self._slot_list(src_zone)
            if key in src:
                src.remove(key)
            self._zones[src_zone].refresh()
        self._slot_list(dst_zone).append(key)
        self._zones[dst_zone].refresh()
        self._status.set_text('Unsaved changes')

    # ── actions ──────────────────────────────────────────────────────────────

    def _on_reload(self, _):
        self._bars = scan_bars()
        self._monitors = self._collect_monitors()
        self._cur_bar = None
        self._left = self._center = self._right = []
        self._stack.set_visible_child_name('empty')
        self._status.set_text('')
        self._populate_monitors()

    def _on_apply(self, _):
        if self._cur_bar is None:
            return
        write_bar_slots(self._cur_bar, self._left, self._center, self._right)
        self._status.set_text('Saved — restarting Waybar…')
        subprocess.Popen(['bash', LAUNCH_WAYBAR])
        GLib.timeout_add(2500, lambda: self._status.set_text('') or False)
