from __future__ import annotations
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw, Gdk, GLib, Pango
import os, subprocess

def _clean_env() -> dict:
    env = dict(os.environ)
    env.pop('LD_PRELOAD', None)
    return env

from constants import LAUNCH_WAYBAR
from models.waybar import (
    scan_bar_styles, scan_config_styles, read_bar_slots, write_bar_slots,
    scan_modules_by_section, BarConfig, BarStyle, init_groups_json,
    build_bar_config, refresh_groups_includes, remove_other_bar_configs,
    active_bar_for_monitor, _known_monitors,
)
from design import current_design

_INVALID = Gtk.INVALID_LIST_POSITION


def _build_key_map(sections: list) -> dict[str, str]:
    return {key: display for _, mods in sections for key, display, *_ in mods}


def _build_desc_map(sections: list) -> dict[str, str]:
    return {key: desc for _, mods in sections for key, _, desc, *_ in mods}


class BarZone(Gtk.Box):
    """Left / center / right drop zone inside the bar preview."""

    def __init__(self, zone_id: str, label: str, on_remove, on_drop, on_add_request):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._zone_id = zone_id
        self._modules: list[str] = []
        self._key_map: dict[str, str] = {}
        self._on_remove = on_remove
        self._on_drop = on_drop

        self.set_vexpand(True)
        self.set_hexpand(True)
        self.add_css_class('bar-zone')

        self._hdr = Gtk.Label(label=label.upper())
        self._hdr.add_css_class('zone-label')
        self._hdr.set_margin_bottom(6)
        self.append(self._hdr)

        self._chips_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        self._chips_box.set_vexpand(True)
        self.append(self._chips_box)

        self._hint = Gtk.Label(label='Click + to add …')
        self._hint.add_css_class('dim-label')
        self._hint.add_css_class('caption')
        self.append(self._hint)

        add_btn = Gtk.Button(icon_name='list-add-symbolic')
        add_btn.add_css_class('flat')
        add_btn.set_tooltip_text('Add module')
        add_btn.connect('clicked', lambda _: on_add_request(zone_id, add_btn))
        self.append(add_btn)

        tgt = Gtk.DropTarget.new(str, Gdk.DragAction.COPY | Gdk.DragAction.MOVE)
        tgt.connect('drop', self._on_drop_cb)
        tgt.connect('enter', self._on_enter)
        tgt.connect('leave', self._on_leave)
        self.add_controller(tgt)

    def set_header_label(self, text: str):
        self._hdr.set_label(text.upper())

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
        chip = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        chip.add_css_class('module-chip')

        if 'separator' in key.lower():
            line = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
            line.set_hexpand(True)
            line.set_valign(Gtk.Align.CENTER)
            chip.append(line)
        else:
            display = self._key_map.get(key, key)
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

    def get_drop_index(self, y: float) -> int:
        idx = 0
        child = self._chips_box.get_first_child()
        while child:
            ok, bounds = child.compute_bounds(self)
            if ok and y < bounds.origin.y + bounds.size.height / 2:
                return idx
            idx += 1
            child = child.get_next_sibling()
        return idx

    def _on_drop_cb(self, _tgt, value: str, x, y) -> bool:
        self.remove_css_class('bar-zone-hover')
        if value.startswith('palette:'):
            self._on_drop(None, self._zone_id, value[8:], y)
            return True
        if value.startswith('zone:'):
            parts = value.split(':', 2)
            if len(parts) == 3:
                self._on_drop(parts[1], self._zone_id, parts[2], y)
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
        self._design_styles: list[str] = scan_config_styles()
        _initial_design = self._design_styles[0] if self._design_styles else ""
        self._bar_styles: list[BarStyle] = scan_bar_styles(_initial_design)
        self._monitors: list[str] = _known_monitors()
        self._cur_bar: BarConfig | None = None
        self._left: list[str] = []
        self._center: list[str] = []
        self._right: list[str] = []
        self._sections_h  = scan_modules_by_section('horizontal',      _initial_design)
        self._sections_vl = scan_modules_by_section('vertical-left',   _initial_design)
        self._sections_vr = scan_modules_by_section('vertical-right',  _initial_design)
        self._map_h   = _build_key_map(self._sections_h)
        self._map_vl  = _build_key_map(self._sections_vl)
        self._map_vr  = _build_key_map(self._sections_vr)
        self._desc_h  = _build_desc_map(self._sections_h)
        self._desc_vl = _build_desc_map(self._sections_vl)
        self._desc_vr = _build_desc_map(self._sections_vr)
        self._zones: dict[str, BarZone] = {}
        self._updating_bars = False
        # Pending combo selections for the active bar, consumed by the _populate_*
        # cascade so opening the page lands on the running bar, not bar/bottom.
        self._want_type: str | None = None
        self._want_variant: str | None = None
        self._want_position: str | None = None

        self._build_ui()
        self._populate_monitors()

    # ── data helpers ────────────────────────────────────────────────────────

    def _cur_design(self) -> str:
        # The design is chosen on the Home page now (overlaid on the wallpaper
        # preview); the waybar page just edits bars for the active design.
        if not self._design_styles:
            return ""
        active = current_design()
        return active if active in self._design_styles else self._design_styles[0]

    def _type_names(self) -> list[str]:
        seen, result = set(), []
        for s in self._bar_styles:
            if not s.is_frame and s.name not in seen:
                seen.add(s.name)
                result.append(s.name)
        if any(s.is_frame for s in self._bar_styles):
            result.append('frame')
        return result

    def _frame_variants(self) -> list[str]:
        return [s.name for s in self._bar_styles if s.is_frame]

    def _cur_type(self) -> str | None:
        names = self._type_names()
        idx = self._style_combo.get_selected()
        if idx == _INVALID or idx >= len(names):
            return None
        return names[idx]

    def _cur_variant(self) -> str | None:
        variants = self._frame_variants()
        idx = self._variant_combo.get_selected()
        if idx == _INVALID or idx >= len(variants):
            return None
        return variants[idx]

    def _positions_for_current(self) -> list[str]:
        type_name = self._cur_type()
        if type_name == 'frame':
            variant = self._cur_variant()
            if variant is None:
                return []
            for s in self._bar_styles:
                if s.name == variant and s.is_frame:
                    return list(s.sub_positions)
            return []
        return [s.position for s in self._bar_styles if s.name == type_name]

    def _cur_position(self) -> str | None:
        positions = self._positions_for_current()
        idx = self._subbar_combo.get_selected()
        if idx == _INVALID or idx >= len(positions):
            return None
        return positions[idx]

    def _cur_bar_style(self) -> BarStyle | None:
        type_name = self._cur_type()
        if type_name == 'frame':
            variant = self._cur_variant()
            for s in self._bar_styles:
                if s.name == variant and s.is_frame:
                    return s
            return None
        for s in self._bar_styles:
            if s.name == type_name:
                return s
        return None

    def _active_key_map(self) -> dict[str, str]:
        mo = self._cur_bar.modules_orientation() if self._cur_bar else 'horizontal'
        return {'vertical-left': self._map_vl, 'vertical-right': self._map_vr}.get(mo, self._map_h)

    def _active_desc_map(self) -> dict[str, str]:
        mo = self._cur_bar.modules_orientation() if self._cur_bar else 'horizontal'
        return {'vertical-left': self._desc_vl, 'vertical-right': self._desc_vr}.get(mo, self._desc_h)

    def _active_sections(self) -> list:
        mo = self._cur_bar.modules_orientation() if self._cur_bar else 'horizontal'
        return {'vertical-left': self._sections_vl, 'vertical-right': self._sections_vr}.get(mo, self._sections_h)

    def _slot_list(self, zone_id: str) -> list[str]:
        return {'left': self._left, 'center': self._center, 'right': self._right}[zone_id]

    # ── UI construction ──────────────────────────────────────────────────────

    def _build_ui(self):
        # SizeGroup ensures all labels share the same width → combos align perfectly
        lbl_grp = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)

        def _sel_row(text, margin_top=6, visible=True):
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10,
                          margin_start=16, margin_end=16, margin_top=margin_top)
            lbl = Gtk.Label(label=text)
            lbl.add_css_class('dim-label')
            lbl.set_halign(Gtk.Align.END)
            lbl_grp.add_widget(lbl)
            row.append(lbl)
            row.set_visible(visible)
            return row

        # The design is selected on the Home page (theme name on the wallpaper
        # preview); this page only edits bars within the active design.

        # ── Monitor-Zeile ─────────────────────────────────────────────────
        mon_row = _sel_row('Monitor')
        self._mon_combo = Gtk.DropDown.new_from_strings([])
        self._mon_combo.set_hexpand(True)
        self._mon_combo.connect('notify::selected', self._on_monitor_changed)
        mon_row.append(self._mon_combo)
        self.append(mon_row)

        # ── Style-Zeile ───────────────────────────────────────────────────
        bar_row = _sel_row('Style')
        self._style_combo = Gtk.DropDown.new_from_strings([])
        self._style_combo.set_hexpand(True)
        self._style_combo.connect('notify::selected', self._on_style_changed)
        bar_row.append(self._style_combo)
        self.append(bar_row)

        # ── Variant-Zeile: nur sichtbar wenn frame gewählt ────────────────
        self._variant_row = _sel_row('Variant', visible=False)
        self._variant_combo = Gtk.DropDown.new_from_strings([])
        self._variant_combo.set_hexpand(True)
        self._variant_combo.connect('notify::selected', self._on_variant_changed)
        self._variant_row.append(self._variant_combo)
        self.append(self._variant_row)

        # ── Position-Zeile ────────────────────────────────────────────────
        self._subbar_row = _sel_row('Position')
        self._subbar_row.set_margin_bottom(6)
        self._subbar_combo = Gtk.DropDown.new_from_strings([])
        self._subbar_combo.set_hexpand(True)
        self._subbar_combo.connect('notify::selected', self._on_subbar_changed)
        self._subbar_row.append(self._subbar_combo)
        self.append(self._subbar_row)

        self.append(Gtk.Separator())

        main = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        main.set_vexpand(True)

        # -- Zones panel (full width) --
        zones_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                               margin_start=16, margin_end=16,
                               margin_top=14, margin_bottom=14)
        zones_panel.set_hexpand(True)

        hdr = Gtk.Label(label='Bar Layout')
        hdr.add_css_class('title-4')
        hdr.set_halign(Gtk.Align.START)
        hdr.set_margin_bottom(2)
        zones_panel.append(hdr)

        self._zones_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self._zones_row.set_vexpand(True)
        self._zones_row.set_homogeneous(True)
        for zone_id, label in [('left', 'Left'), ('center', 'Center'), ('right', 'Right')]:
            z = BarZone(zone_id, label, self._on_remove, self._on_zone_drop,
                        self._on_add_request)
            self._zones[zone_id] = z
            self._zones_row.append(z)
        zones_panel.append(self._zones_row)

        empty = Adw.StatusPage()
        empty.set_icon_name('view-grid-symbolic')
        empty.set_title('No bars configured')
        empty.set_description('Run waybar.sh to set up bars first, then reload here.')
        empty.set_vexpand(True)

        self._stack = Gtk.Stack()
        self._stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self._stack.add_named(empty,                  'empty')
        self._stack.add_named(zones_panel,            'zones')
        self._stack.add_named(self._build_add_page(), 'add')
        self._stack.set_visible_child_name('empty')
        main.append(self._stack)

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

    def _populate_styles(self):
        names = self._type_names()
        strings = Gtk.StringList()
        for n in names:
            strings.append(n)
        self._updating_bars = True
        self._style_combo.set_model(strings)
        sel, self._want_type = self._want_type, None
        if sel is not None and sel in names:
            self._style_combo.set_selected(names.index(sel))
        self._updating_bars = False
        self._populate_variants()

    def _populate_variants(self):
        is_frame = self._cur_type() == 'frame'
        self._variant_row.set_visible(is_frame)
        if is_frame:
            variants = self._frame_variants()
            strings = Gtk.StringList()
            for v in variants:
                strings.append(v)
            self._updating_bars = True
            self._variant_combo.set_model(strings)
            sel, self._want_variant = self._want_variant, None
            if sel is not None and sel in variants:
                self._variant_combo.set_selected(variants.index(sel))
            self._updating_bars = False
        self._populate_positions()

    def _populate_positions(self):
        positions = self._positions_for_current()
        strings = Gtk.StringList()
        for p in positions:
            strings.append(p)
        self._updating_bars = True
        self._subbar_combo.set_model(strings)
        sel, self._want_position = self._want_position, None
        if sel is not None and sel in positions:
            self._subbar_combo.set_selected(positions.index(sel))
        self._updating_bars = False
        self._resolve_bar()

    def _set_wants_for_monitor(self, monitor: str | None) -> str | None:
        """Queue the active bar's type/variant/position for `monitor` so the page
        opens on the running bar. Returns its design, or None if no active bar."""
        self._want_type = self._want_variant = self._want_position = None
        active = active_bar_for_monitor(monitor) if monitor else None
        if not active:
            return None
        design, style, position = active
        self._want_position = position
        bs = next((s for s in scan_bar_styles(design) if s.name == style), None)
        if bs and bs.is_frame:
            self._want_type, self._want_variant = 'frame', style
        else:
            self._want_type = style
        return design

    def _on_monitor_changed(self, combo, _):
        mon_idx = self._mon_combo.get_selected()
        monitor = self._monitors[mon_idx] if (mon_idx != _INVALID and self._monitors) else None
        self._set_wants_for_monitor(monitor)
        self._populate_styles()

    def _on_style_changed(self, combo, _):
        if self._updating_bars:
            return
        self._populate_variants()

    def _on_variant_changed(self, combo, _):
        if self._updating_bars:
            return
        self._populate_positions()

    def _on_subbar_changed(self, combo, _):
        if self._updating_bars:
            return
        self._resolve_bar()

    def _resolve_bar(self):
        mon_idx = self._mon_combo.get_selected()
        type_name = self._cur_type()
        position = self._cur_position()
        if mon_idx == _INVALID or not self._monitors or type_name is None or position is None:
            self._cur_bar = None
            self._stack.set_visible_child_name('empty')
            return
        monitor = self._monitors[mon_idx]
        style_name = self._cur_variant() if type_name == 'frame' else type_name
        if style_name is None:
            self._cur_bar = None
            self._stack.set_visible_child_name('empty')
            return
        bar = BarConfig(style=style_name, position=position, monitor=monitor,
                        design=self._cur_design())
        init_groups_json(bar)
        left, center, right = read_bar_slots(bar)
        self._cur_bar = bar
        self._left, self._center, self._right = list(left), list(center), list(right)
        self._status.set_text('')
        self._update_zones_layout(bar.orientation() == 'vertical')
        self._refresh_zones()
        self._stack.set_visible_child_name('zones')

    # ── zone / palette refresh ───────────────────────────────────────────────

    def _refresh_zones(self):
        key_map = self._active_key_map()
        for zone_id, mods in [('left', self._left), ('center', self._center), ('right', self._right)]:
            self._zones[zone_id].set_data(mods, key_map)

    def _update_zones_layout(self, is_vertical: bool):
        if is_vertical:
            self._zones_row.set_orientation(Gtk.Orientation.VERTICAL)
            labels = {'left': 'Top', 'center': 'Middle', 'right': 'Bottom'}
        else:
            self._zones_row.set_orientation(Gtk.Orientation.HORIZONTAL)
            labels = {'left': 'Left', 'center': 'Center', 'right': 'Right'}
        for zone_id, label in labels.items():
            self._zones[zone_id].set_header_label(label)

    def _build_add_page(self) -> Gtk.Box:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        page.set_hexpand(True)

        # Header with back button + zone name
        hdr_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                          margin_start=16, margin_end=16,
                          margin_top=10, margin_bottom=10)
        back_btn = Gtk.Button(icon_name='go-previous-symbolic')
        back_btn.add_css_class('flat')
        back_btn.connect('clicked', lambda _: self._stack.set_visible_child_name('zones'))
        hdr_box.append(back_btn)

        self._add_zone_label = Gtk.Label()
        self._add_zone_label.add_css_class('title-4')
        self._add_zone_label.set_halign(Gtk.Align.START)
        self._add_zone_label.set_hexpand(True)
        hdr_box.append(self._add_zone_label)
        page.append(hdr_box)
        page.append(Gtk.Separator())

        # Search bar
        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL,
                             margin_start=16, margin_end=16,
                             margin_top=8, margin_bottom=4)
        self._add_search = Gtk.SearchEntry()
        self._add_search.set_placeholder_text('Search modules…')
        self._add_search.set_hexpand(True)
        self._add_search.connect('search-changed', self._on_add_search_changed)
        search_box.append(self._add_search)
        page.append(search_box)

        # Scrollable module sections
        sc = Gtk.ScrolledWindow()
        sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sc.set_vexpand(True)
        self._add_modules_box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL, spacing=0,
            margin_start=16, margin_end=16, margin_bottom=16)
        sc.set_child(self._add_modules_box)
        page.append(sc)

        self._add_sections: list[tuple] = []  # (hdr, flow, [(key, display)])
        self._add_target_zone = 'left'
        return page

    def _populate_add_page(self):
        child = self._add_modules_box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._add_modules_box.remove(child)
            child = nxt
        self._add_sections = []

        desc_map = self._active_desc_map()
        for section, mods in self._active_sections():
            if not mods:
                continue
            hdr = Gtk.Label(label=section.upper())
            hdr.add_css_class('palette-section-label')
            hdr.set_halign(Gtk.Align.START)
            hdr.set_margin_top(12)
            hdr.set_margin_bottom(4)
            self._add_modules_box.append(hdr)

            flow = Gtk.FlowBox()
            flow.set_selection_mode(Gtk.SelectionMode.NONE)
            flow.set_column_spacing(6)
            flow.set_row_spacing(6)
            flow.set_min_children_per_line(3)
            flow.set_max_children_per_line(8)
            for key, display, *_ in mods:
                fchild = Gtk.FlowBoxChild()
                fchild.set_focusable(False)
                btn = Gtk.Button(label=display)
                btn.add_css_class('palette-chip')
                btn.set_tooltip_text(desc_map.get(key, key))
                btn.connect('clicked', lambda _, k=key: self._on_add_module(k))
                fchild.set_child(btn)
                flow.append(fchild)
            self._add_modules_box.append(flow)
            self._add_sections.append((hdr, flow, [(k, d) for k, d, *_ in mods]))

    def _on_add_request(self, zone_id: str, _parent: Gtk.Widget):
        self._add_target_zone = zone_id
        zone_labels_h = {'left': 'Left',  'center': 'Center', 'right': 'Right'}
        zone_labels_v = {'left': 'Top',   'center': 'Middle', 'right': 'Bottom'}
        labels = (zone_labels_v
                  if (self._cur_bar and self._cur_bar.orientation() == 'vertical')
                  else zone_labels_h)
        self._add_zone_label.set_label(f'Add to {labels.get(zone_id, zone_id)}')
        self._populate_add_page()
        self._add_search.set_text('')
        self._stack.set_visible_child_name('add')

    def _on_add_module(self, key: str):
        # Append at the bottom of the zone (drag-and-drop still places freely).
        dst_list = self._slot_list(self._add_target_zone)
        dst_list.append(key)
        self._zones[self._add_target_zone].refresh()
        self._status.set_text('Unsaved changes')
        self._stack.set_visible_child_name('zones')

    def _on_add_search_changed(self, _):
        q = self._add_search.get_text().lower()
        for hdr, flow, mods in self._add_sections:
            if not q:
                hdr.set_visible(True)
                flow.set_visible(True)
                flow.set_filter_func(None)
            else:
                def _filt(child, _q=q):
                    btn = child.get_child()
                    return _q in btn.get_label().lower()
                flow.set_filter_func(_filt)
                any_match = any(q in d.lower() or q in k.lower() for k, d in mods)
                hdr.set_visible(any_match)
                flow.set_visible(any_match)

    # ── DnD / edit callbacks ─────────────────────────────────────────────────

    def _on_remove(self, zone_id: str, key: str):
        mods = self._slot_list(zone_id)
        if key in mods:
            mods.remove(key)
        self._zones[zone_id].refresh()
        self._status.set_text('Unsaved changes')

    def _on_zone_drop(self, src_zone: str | None, dst_zone: str, key: str, y: float = 0):
        dst_list = self._slot_list(dst_zone)
        insert_idx = self._zones[dst_zone].get_drop_index(y)
        if src_zone is not None:
            src = self._slot_list(src_zone)
            if key in src:
                if src_zone == dst_zone:
                    old_idx = src.index(key)
                    src.remove(key)
                    if old_idx < insert_idx:
                        insert_idx -= 1
                else:
                    src.remove(key)
                    self._zones[src_zone].refresh()
        insert_idx = max(0, min(insert_idx, len(dst_list)))
        dst_list.insert(insert_idx, key)
        self._zones[dst_zone].refresh()
        self._status.set_text('Unsaved changes')

    # ── actions ──────────────────────────────────────────────────────────────

    def _on_reload(self, _):
        self._design_styles = scan_config_styles()
        design = self._cur_design()
        self._bar_styles = scan_bar_styles(design)
        self._sections_h  = scan_modules_by_section('horizontal',     design)
        self._sections_vl = scan_modules_by_section('vertical-left',  design)
        self._sections_vr = scan_modules_by_section('vertical-right', design)
        self._map_h   = _build_key_map(self._sections_h)
        self._map_vl  = _build_key_map(self._sections_vl)
        self._map_vr  = _build_key_map(self._sections_vr)
        self._desc_h  = _build_desc_map(self._sections_h)
        self._desc_vl = _build_desc_map(self._sections_vl)
        self._desc_vr = _build_desc_map(self._sections_vr)
        self._monitors = _known_monitors()
        self._cur_bar = None
        self._left, self._center, self._right = [], [], []
        self._status.set_text('')
        self._populate_monitors()
        self._populate_styles()

    def _on_apply(self, _):
        if self._cur_bar is None:
            self._status.set_text('Error: no bar selected')
            return
        try:
            monitor = self._cur_bar.monitor
            style = self._cur_bar_style()

            remove_other_bar_configs(monitor, self._cur_bar.style, self._cur_bar.design, self._cur_bar.position)
            refresh_groups_includes(self._cur_bar)
            write_bar_slots(self._cur_bar, self._left, self._center, self._right)
            build_bar_config(self._cur_bar)

            if style and style.is_frame:
                for pos in style.sub_positions:
                    if pos == self._cur_bar.position:
                        continue
                    sibling = BarConfig(style=self._cur_bar.style, position=pos, monitor=monitor,
                                       design=self._cur_bar.design)
                    init_groups_json(sibling)
                    refresh_groups_includes(sibling)
                    build_bar_config(sibling)

            cfg = __import__('os').path.join(
                __import__('os').path.dirname(self._cur_bar.groups_file), 'config.json')
            if not __import__('os').path.exists(cfg):
                self._status.set_text('Error: base template missing for this style')
                return

            self._status.set_text('Saved — restarting Waybar…')
            subprocess.Popen(['bash', LAUNCH_WAYBAR], env=_clean_env())
            # The chosen design also themes hyprland/swaync/gui.
            if self._cur_bar.design:
                self._apply_app_theme(self._cur_bar.design)
            GLib.timeout_add(2500, lambda: self._status.set_text('') or False)
        except Exception as e:
            self._status.set_text(f'Error: {e}')

    def _apply_app_theme(self, design: str):
        """Record the active design and reload the apps that theme off it:
        swaync, hyprland, and the running GUI (live)."""
        base = os.environ.get('VUTURELAND_USER_DIR') or os.path.join(
            os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config')), 'vutureland')
        try:
            with open(os.path.join(base, 'active-theme'), 'w') as f:
                f.write(design + '\n')
        except OSError:
            pass
        # GUI: restyle live (function lives in the running app's main module)
        import sys
        for modname in ('__main__', 'main'):
            m = sys.modules.get(modname)
            fn = getattr(m, 'reload_design_theme', None) if m else None
            if fn:
                try:
                    fn()
                except Exception:
                    pass
                break
        # swaync (re-reads active-theme) + hyprland (hyprctl reload re-runs the config)
        vtl = os.environ.get('VUTURELAND_DIR') or os.path.realpath(
            os.path.join(os.path.dirname(__file__), '..', '..'))
        try:
            subprocess.Popen(['bash', os.path.join(vtl, 'assets', 'scripts', 'launch-swaync.sh')],
                             env=_clean_env())
        except Exception:
            pass
        try:
            subprocess.Popen(['hyprctl', 'reload'], env=_clean_env())
        except Exception:
            pass
