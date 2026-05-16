import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw
import subprocess
from constants import AVAILABLE_MODULES, LAUNCH_WAYBAR
from models.waybar import read_bars, read_groups, write_groups


class SlotBox(Gtk.Box):
    def __init__(self, label: str, modules_list: list, on_change):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._mods = modules_list
        self._on_change = on_change

        lbl = Gtk.Label(label=label, halign=Gtk.Align.START)
        lbl.add_css_class('heading')
        self.append(lbl)

        self._list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.append(self._list_box)

        add_btn = Gtk.Button(icon_name='list-add-symbolic')
        add_btn.add_css_class('flat')
        add_btn.set_halign(Gtk.Align.START)
        add_btn.connect('clicked', self._show_picker)
        self.append(add_btn)

        self._refresh()

    def _refresh(self):
        child = self._list_box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._list_box.remove(child)
            child = nxt
        for mod in self._mods:
            self._list_box.append(self._make_row(mod))

    def _make_row(self, mod: str) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        lbl = Gtk.Label(label=mod, halign=Gtk.Align.START, hexpand=True)
        lbl.add_css_class('monospace')
        rm = Gtk.Button(icon_name='list-remove-symbolic')
        rm.add_css_class('flat')
        rm.connect('clicked', lambda _, m=mod: self._remove(m))
        box.append(lbl)
        box.append(rm)
        return box

    def _remove(self, mod: str):
        if mod in self._mods:
            self._mods.remove(mod)
        self._refresh()
        self._on_change()

    def _show_picker(self, btn):
        pop = Gtk.Popover()
        pop.set_parent(btn)
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2,
                        margin_top=6, margin_bottom=6,
                        margin_start=6, margin_end=6)
        for m in AVAILABLE_MODULES:
            b = Gtk.Button(label=m, halign=Gtk.Align.START)
            b.add_css_class('flat')
            b.add_css_class('monospace')
            b.connect('clicked', lambda _, mod=m, p=pop: self._pick(mod, p))
            inner.append(b)
        sc = Gtk.ScrolledWindow()
        sc.set_size_request(260, 280)
        sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sc.set_child(inner)
        pop.set_child(sc)
        pop.popup()

    def _pick(self, mod: str, pop: Gtk.Popover):
        if mod not in self._mods:
            self._mods.append(mod)
        pop.popdown()
        self._refresh()
        self._on_change()


class WaybarPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__()
        self._bars   = read_bars()
        self._groups = read_groups()
        self._build()

    def _build(self):
        for bar in self._bars:
            group = Adw.PreferencesGroup(title=f'Monitor: {bar.get("output", "?")}')
            slots_row = Adw.ActionRow()
            slots_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=20,
                                margin_top=10, margin_bottom=10)
            slots_box.set_homogeneous(True)

            for slot, label in [('left', 'Links'), ('center', 'Mitte'), ('right', 'Rechts')]:
                group_key = bar.get(slot, '')
                if group_key not in self._groups:
                    self._groups[group_key] = {'orientation': 'horizontal', 'modules': []}
                if 'modules' not in self._groups[group_key]:
                    self._groups[group_key]['modules'] = []
                mods = self._groups[group_key]['modules']
                sb = SlotBox(label, mods, self._mark_changed)
                sb.set_hexpand(True)
                slots_box.append(sb)

            slots_row.set_child(slots_box)
            group.add(slots_row)
            self.add(group)

        apply_group = Adw.PreferencesGroup()
        self._apply_btn = Gtk.Button(label='Waybar neu starten')
        self._apply_btn.add_css_class('suggested-action')
        self._apply_btn.add_css_class('pill')
        self._apply_btn.connect('clicked', self._apply)
        apply_group.add(self._apply_btn)
        self.add(apply_group)

    def _mark_changed(self):
        self._apply_btn.set_label('Waybar neu starten *')

    def _apply(self, _):
        write_groups(self._groups)
        subprocess.Popen(['bash', LAUNCH_WAYBAR])
        self._apply_btn.set_label('Waybar neu starten')
