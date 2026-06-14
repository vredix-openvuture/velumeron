#!/usr/bin/env python3
"""Vutureland — UFW Firewall Manager

Sorted view : Gtk.ColumnView with resizable columns.
Grouped view: Adw.PreferencesGroup sections (one per group).
Privilege   : sudo -n first, pkexec fallback.
"""

import gi, os, json, re, subprocess, sys, threading
from dataclasses import dataclass
from collections import defaultdict
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib, Gdk, Gio, GObject

# ── Paths ─────────────────────────────────────────────────────────────────────
_XDG_CFG       = os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config'))
_VTL           = os.path.realpath(os.environ.get('VUTURELAND_DIR') or
                                   os.path.join(os.path.dirname(__file__), '..'))
_VTL_USER      = os.environ.get('VUTURELAND_USER_DIR') or os.path.join(_XDG_CFG, 'vutureland')
_CSS_BASE      = os.path.join(os.path.dirname(__file__), 'style.css')
_CSS_COLORS    = os.path.join(_VTL_USER, 'assets', 'colors_gtk.css')
_CSS_COLORS_FB = os.path.join(_VTL, 'assets', 'colors_gtk.css')
_META_FILE     = os.path.join(_VTL_USER, 'ufw-rules.json')

# ── Column spec: (key, header, initial_px, expands) ──────────────────────────
_COLS = [
    ('action',    'Action',    80,  False),
    ('port',      'Port',     110,  False),
    ('proto',     'Protocol',  80,  False),
    ('direction', 'Direction', 80,  False),
    ('tag',       'Tag',      100,  False),
    ('comment',   'Comment',    0,  True ),   # expands to fill remaining space
    ('group',     'Group',     90,  False),
    ('_del',      '',          50,  False),
]

_ACTIONS = ['ALLOW', 'DENY', 'REJECT']
_PROTOS  = ['tcp', 'udp', '']
_DIRS    = ['IN', 'OUT', '']


# ── Rule ──────────────────────────────────────────────────────────────────────

@dataclass
class Rule:
    num:       int
    port:      str
    proto:     str
    action:    str
    direction: str
    comment:   str
    tag:       str
    group:     str

    @property
    def ufw_target(self) -> str:
        return f'{self.port}/{self.proto}' if self.proto else self.port

    @property
    def meta_key(self) -> str:
        return self.ufw_target


# ── GObject wrapper (required for Gio.ListStore) ──────────────────────────────

class RuleObject(GObject.Object):
    __gtype_name__ = 'UfwRuleObject'
    def __init__(self, rule: Rule):
        super().__init__()
        self.rule = rule


# ── Metadata ──────────────────────────────────────────────────────────────────

def _load_meta() -> dict:
    try:
        with open(_META_FILE) as f:
            return json.load(f)
    except Exception:
        return {}

def _save_meta(meta: dict) -> None:
    try:
        os.makedirs(os.path.dirname(_META_FILE), exist_ok=True)
        with open(_META_FILE, 'w') as f:
            json.dump(meta, f, indent=2)
    except Exception as e:
        print(f'[ufw-meta] {e}', file=sys.stderr)


# ── UFW privileged backend ────────────────────────────────────────────────────

_HELPER = os.path.join(os.path.dirname(__file__), 'ufw_helper.py')


class _UfwBackend:
    """Single pkexec session — authenticates once, stays alive for the app."""

    def __init__(self):
        self._proc: subprocess.Popen | None = None

    def alive(self) -> bool:
        return self._proc is not None and self._proc.poll() is None

    def start(self) -> tuple[bool, str]:
        """Launch the helper via pkexec (polkit dialog, blocks until done)."""
        if self.alive():
            return True, ''
        try:
            proc = subprocess.Popen(
                ['pkexec', sys.executable, _HELPER],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True, bufsize=1,
            )
        except FileNotFoundError as e:
            return False, str(e)
        line = proc.stdout.readline().strip()
        if line != 'READY':
            err = proc.stderr.read().strip()
            proc.kill()
            proc.wait()
            return False, err or 'Authentication was cancelled or failed.'
        self._proc = proc
        return True, ''

    def run(self, *args) -> tuple[int, str]:
        if not self.alive():
            return 1, 'Not authenticated — please restart the application.'
        cmd = '\x00'.join(args) + '\n'
        self._proc.stdin.write(cmd)
        self._proc.stdin.flush()
        line = self._proc.stdout.readline()
        if not line:
            self._proc = None
            return 1, 'Helper process terminated unexpectedly.'
        rc_str, out_enc = line.strip().split('\x00', 1)
        return int(rc_str), out_enc.replace('\x01', '\n')

    def stop(self):
        if self._proc:
            try:
                self._proc.stdin.close()
                self._proc.wait(timeout=3)
            except Exception:
                self._proc.kill()
            self._proc = None


def _parse_rules(output: str, meta: dict) -> tuple[bool, list[Rule]]:
    active = 'Status: active' in output
    rules: list[Rule] = []
    for line in output.splitlines():
        line = line.strip()
        m = re.match(r'^\[\s*(\d+)\]\s+(.+)$', line)
        if not m:
            continue
        num  = int(m.group(1))
        rest = m.group(2)
        comment = ''
        if '#' in rest:
            ci      = rest.index('#')
            comment = rest[ci + 1:].strip()
            rest    = rest[:ci]
        am = re.search(r'\b(ALLOW|DENY|REJECT)\s*(IN|OUT)?\b', rest)
        if not am:
            continue
        to        = rest[:am.start()].strip()
        action    = am.group(1)
        direction = am.group(2) or ''
        if '(v6)' in to:
            continue
        port, proto = (to.rsplit('/', 1) if '/' in to else (to, ''))
        rm = meta.get(to, {})
        rules.append(Rule(num=num, port=port, proto=proto,
                          action=action, direction=direction,
                          comment=comment,
                          tag=rm.get('tag', ''),
                          group=rm.get('group', '')))
    return active, rules


# ── Window ────────────────────────────────────────────────────────────────────

class UfwManagerWindow(Adw.ApplicationWindow):

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title('UFW Firewall')
        self.set_default_size(960, 560)
        self._meta:       dict        = _load_meta()
        self._rules:      list[Rule]  = []
        self._ufw_active: bool        = False
        self._filter_tag: str         = ''
        self._sort_key:   str         = 'port'
        self._sort_asc:   bool        = True
        self._group_view: bool        = False
        self._backend:    _UfwBackend = _UfwBackend()
        self._build_ui()
        self.connect('close-request', self._on_close)
        GLib.idle_add(self._start_auth)

    # ── Build ─────────────────────────────────────────────────────────────────

    def _build_ui(self):
        hdr = Adw.HeaderBar()

        # Left: UFW status toggle + add button
        dot_box = Gtk.Box(spacing=4)
        self._dot = Gtk.Label(label='●')
        self._status_lbl = Gtk.Label(label='…')
        dot_box.append(self._dot)
        dot_box.append(self._status_lbl)
        self._toggle_btn = Gtk.Button()
        self._toggle_btn.set_child(dot_box)
        self._toggle_btn.add_css_class('flat')
        self._toggle_btn.set_tooltip_text('Toggle UFW on / off')
        self._toggle_btn.connect('clicked', self._on_toggle_ufw)
        hdr.pack_start(self._toggle_btn)

        add_btn = Gtk.Button.new_from_icon_name('list-add-symbolic')
        add_btn.add_css_class('flat')
        add_btn.set_tooltip_text('Add rule  (Ctrl+N)')
        add_btn.connect('clicked', self._on_add_dialog)
        hdr.pack_start(add_btn)

        # Right: refresh, group toggle, sort, tag filter
        refresh_btn = Gtk.Button.new_from_icon_name('view-refresh-symbolic')
        refresh_btn.add_css_class('flat')
        refresh_btn.set_tooltip_text('Refresh')
        refresh_btn.connect('clicked', lambda _: self._refresh())
        hdr.pack_end(refresh_btn)

        self._group_btn = Gtk.ToggleButton()
        self._group_btn.set_icon_name('view-list-symbolic')
        self._group_btn.add_css_class('flat')
        self._group_btn.set_tooltip_text('Show groups')
        self._group_btn.connect('toggled', self._on_group_toggled)
        hdr.pack_end(self._group_btn)

        self._sort_menu = Gtk.MenuButton()
        self._sort_menu.set_icon_name('view-sort-ascending-symbolic')
        self._sort_menu.add_css_class('flat')
        self._sort_menu.set_tooltip_text('Sort')
        self._sort_menu.set_popover(self._build_sort_popover())
        hdr.pack_end(self._sort_menu)

        self._filter_menu = Gtk.MenuButton()
        self._filter_menu.set_label('All tags')
        self._filter_menu.add_css_class('flat')
        self._filter_menu.set_tooltip_text('Filter by tag')
        self._filter_popover = self._build_filter_popover()
        self._filter_menu.set_popover(self._filter_popover)
        hdr.pack_end(self._filter_menu)

        # ── Stack: sorted (ColumnView) ↔ grouped (PreferencesGroups) ──────────
        self._stack = Gtk.Stack()
        self._stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self._stack.set_transition_duration(120)

        # Sorted view — Gtk.ColumnView
        self._store = Gio.ListStore.new(RuleObject)
        self._cv = Gtk.ColumnView.new(Gtk.NoSelection.new(self._store))
        self._cv.set_reorderable(False)
        self._cv.set_show_row_separators(True)
        self._cv.set_hexpand(True)
        self._cv.add_css_class('ufw-cv')
        for key, title, width, flex in _COLS:
            self._cv.append_column(self._make_cv_column(key, title, width, flex))

        scroll_cv = Gtk.ScrolledWindow()
        scroll_cv.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll_cv.set_vexpand(True)
        scroll_cv.set_child(self._cv)
        self._stack.add_named(scroll_cv, 'sorted')

        # Grouped view — scrollable Gtk.Box with Adw.PreferencesGroup sections
        self._group_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        self._group_box.set_margin_top(16)
        self._group_box.set_margin_bottom(16)
        self._group_box.set_margin_start(16)
        self._group_box.set_margin_end(16)

        scroll_grp = Gtk.ScrolledWindow()
        scroll_grp.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll_grp.set_vexpand(True)
        scroll_grp.set_child(self._group_box)
        self._stack.add_named(scroll_grp, 'grouped')

        view = Adw.ToolbarView()
        view.add_top_bar(hdr)
        view.set_content(self._stack)
        self.set_content(view)

        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect('key-pressed', self._on_key)
        self.add_controller(key_ctrl)

    # ── ColumnView column factory ─────────────────────────────────────────────

    def _make_cv_column(self, key: str, title: str, width: int,
                         flex: bool) -> Gtk.ColumnViewColumn:
        factory = Gtk.SignalListItemFactory()

        def setup(_f, item):
            if key == '_del':
                btn = Gtk.Button.new_from_icon_name('user-trash-symbolic')
                btn.add_css_class('flat')
                btn.add_css_class('destructive-action')
                btn.set_tooltip_text('Delete rule')
                btn.set_valign(Gtk.Align.CENTER)
            else:
                lbl = Gtk.Label(label='')
                lbl.set_xalign(0)
                lbl.set_ellipsize(3)   # Pango.EllipsizeMode.END
                lbl.set_hexpand(True)
                btn = Gtk.Button()
                btn.add_css_class('flat')
                btn.set_child(lbl)
            btn.add_css_class('ufw-cell')

            # Closure captures `item`; item.get_item() always returns the
            # currently bound RuleObject — correct even after list recycling.
            def _click(_b, _item=item):
                obj = _item.get_item()
                if obj is None:
                    return
                if key == '_del':
                    self._confirm_delete(obj.rule)
                else:
                    self._on_cell_click(_b, obj.rule, key)

            btn.connect('clicked', _click)
            item.set_child(btn)

        def bind(_f, item):
            if key == '_del':
                return
            obj = item.get_item()
            if obj is None:
                return
            btn   = item.get_child()
            lbl   = btn.get_child()   # Gtk.Label set in setup
            value = self._cell_display(obj.rule, key)
            lbl.set_label(value or '—')
            if value:
                lbl.remove_css_class('ufw-cell-empty')
            else:
                lbl.add_css_class('ufw-cell-empty')

        factory.connect('setup', setup)
        factory.connect('bind', bind)

        col = Gtk.ColumnViewColumn(title=title, factory=factory)
        col.set_resizable(key != '_del')
        if flex:
            col.set_expand(True)
        else:
            col.set_fixed_width(width)

        if key != '_del':
            # Minimum: at least wide enough to show the column header label.
            # fixed-width is -1 when unset; only clamp strictly positive values.
            _min_w = max(56, len(title) * 8 + 24)
            def _clamp(c, _p, _m=_min_w):
                w = c.get_fixed_width()
                if 0 < w < _m:
                    c.set_fixed_width(_m)
            col.connect('notify::fixed-width', _clamp)

        return col

    # ── Authentication ────────────────────────────────────────────────────────

    def _start_auth(self) -> bool:
        self._status_lbl.set_label('authenticating…')
        threading.Thread(target=self._auth_thread, daemon=True).start()
        return False

    def _auth_thread(self):
        ok, err = self._backend.start()
        GLib.idle_add(self._on_auth_done, ok, err)

    def _on_auth_done(self, ok: bool, err: str) -> bool:
        if not ok:
            d = Adw.AlertDialog(
                heading='Authentication Failed',
                body=(err or 'Could not obtain elevated privileges.') +
                     '\n\nMake sure a polkit agent (e.g. polkit-gnome) is running.',
            )
            d.add_response('quit', 'Quit')
            d.connect('response', lambda *_: self.get_application().quit())
            d.present(self)
            return False
        self._refresh()
        return False

    def _on_close(self, _win) -> bool:
        self._backend.stop()
        return False

    # ── Refresh ───────────────────────────────────────────────────────────────

    def _refresh(self) -> bool:
        rc, out = self._backend.run('status', 'numbered')
        if rc != 0:
            self._set_dot(error=True)
            self._show_error('UFW Error',
                (out or 'Cannot read UFW status.') +
                '\n\nMake sure UFW is installed and sudo / polkit access is available.')
            return False
        active, rules = _parse_rules(out, self._meta)
        self._ufw_active = active
        self._rules      = rules
        self._set_dot(active=active)
        self._update_tag_filter_list()
        self._rebuild_table()
        return False

    def _set_dot(self, active=False, error=False):
        if error:
            self._dot.set_label('○')
            self._dot.set_css_classes(['dim-label'])
            self._status_lbl.set_label('error')
        elif active:
            self._dot.set_label('●')
            self._dot.set_css_classes(['success'])
            self._status_lbl.set_label('enabled')
        else:
            self._dot.set_label('○')
            self._dot.set_css_classes(['dim-label'])
            self._status_lbl.set_label('disabled')

    # ── Table rebuild ─────────────────────────────────────────────────────────

    def _visible_rules(self) -> list[Rule]:
        rules = self._rules
        if self._filter_tag:
            rules = [r for r in rules if r.tag == self._filter_tag]
        key_fn = ((lambda r: (self._port_num(r.port), r.proto))
                  if self._sort_key == 'port' else
                  (lambda r: r.comment.lower()))
        return sorted(rules, key=key_fn, reverse=not self._sort_asc)

    @staticmethod
    def _port_num(port: str) -> tuple:
        m = re.match(r'^(\d+)', port)
        return (int(m.group(1)) if m else 99999, port)

    def _rebuild_table(self):
        rules = self._visible_rules()
        if self._group_view:
            self._stack.set_visible_child_name('grouped')
            self._rebuild_grouped(rules)
        else:
            self._stack.set_visible_child_name('sorted')
            self._rebuild_sorted(rules)

    def _rebuild_sorted(self, rules: list[Rule]):
        self._store.remove_all()
        if not rules:
            return
        for r in rules:
            self._store.append(RuleObject(r))

    def _rebuild_grouped(self, rules: list[Rule]):
        while (ch := self._group_box.get_first_child()):
            self._group_box.remove(ch)

        if not rules:
            lbl = Gtk.Label(label='No rules match the current filter.')
            lbl.add_css_class('dim-label')
            lbl.set_margin_top(24)
            self._group_box.append(lbl)
            return

        groups: dict[str, list[Rule]] = defaultdict(list)
        for r in rules:
            groups[r.group or '(no group)'].append(r)

        for gname in sorted(groups):
            grp = Adw.PreferencesGroup(title=gname)
            for rule in groups[gname]:
                grp.add(self._make_group_row(rule))
            self._group_box.append(grp)

    def _make_group_row(self, rule: Rule) -> Adw.ActionRow:
        row = Adw.ActionRow()
        row.set_title(rule.comment or rule.ufw_target)
        parts = [rule.ufw_target,
                 rule.action + (f' {rule.direction}' if rule.direction else '')]
        if rule.tag:
            parts.append(f'#{rule.tag}')
        row.set_subtitle('  ·  '.join(parts))

        edit_btn = Gtk.Button.new_from_icon_name('document-edit-symbolic')
        edit_btn.add_css_class('flat')
        edit_btn.set_valign(Gtk.Align.CENTER)
        edit_btn.set_tooltip_text('Edit comment')
        edit_btn.connect('clicked', lambda _b, r=rule: self._popover_entry(_b, r, 'comment'))
        row.add_suffix(edit_btn)

        del_btn = Gtk.Button.new_from_icon_name('user-trash-symbolic')
        del_btn.add_css_class('flat')
        del_btn.add_css_class('destructive-action')
        del_btn.set_valign(Gtk.Align.CENTER)
        del_btn.set_tooltip_text('Delete rule')
        del_btn.connect('clicked', lambda _b, r=rule: self._confirm_delete(r))
        row.add_suffix(del_btn)
        return row

    # ── Cell display ──────────────────────────────────────────────────────────

    def _cell_display(self, r: Rule, key: str) -> str:
        if key == 'action':    return r.action
        if key == 'port':      return r.port
        if key == 'proto':     return r.proto or 'tcp+udp'
        if key == 'direction': return r.direction or 'in+out'
        if key == 'tag':       return f'#{r.tag}' if r.tag else ''
        if key == 'comment':   return r.comment
        if key == 'group':     return r.group
        return ''

    # ── Cell click → popover ──────────────────────────────────────────────────

    def _on_cell_click(self, btn: Gtk.Button, rule: Rule, key: str):
        if key in ('action', 'proto', 'direction'):
            self._popover_choice(btn, rule, key)
        else:
            self._popover_entry(btn, rule, key)

    def _popover_entry(self, anchor: Gtk.Widget, rule: Rule, key: str):
        current = {'port': rule.port, 'comment': rule.comment,
                   'tag': rule.tag, 'group': rule.group}.get(key, '')
        entry = Gtk.Entry()
        entry.set_text(current)
        entry.set_size_request(220, -1)
        save_btn = Gtk.Button(label='Save')
        save_btn.add_css_class('suggested-action')
        box = Gtk.Box(spacing=6)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(8)
        box.set_margin_end(8)
        box.append(entry)
        box.append(save_btn)
        pop = Gtk.Popover()
        pop.set_child(box)
        pop.set_parent(anchor)
        pop.set_autohide(True)

        def _save(_=None):
            val = entry.get_text().strip()
            pop.popdown()
            self._apply_change(rule, key, val)

        save_btn.connect('clicked', _save)
        entry.connect('activate', _save)
        pop.popup()
        entry.grab_focus()

    def _popover_choice(self, anchor: Gtk.Widget, rule: Rule, key: str):
        cfg = {
            'action':    (list(zip(_ACTIONS, _ACTIONS)),         rule.action),
            'proto':     ([('tcp','TCP'),('udp','UDP'),('','TCP+UDP')], rule.proto),
            'direction': ([('IN','In'),('OUT','Out'),('','In+Out')],    rule.direction),
        }[key]
        pairs, current = cfg

        lb  = Gtk.ListBox()
        lb.set_selection_mode(Gtk.SelectionMode.NONE)
        lb.add_css_class('boxed-list')
        pop = Gtk.Popover()

        for val, label in pairs:
            inner = Gtk.Box(spacing=6)
            inner.set_margin_top(5)
            inner.set_margin_bottom(5)
            inner.set_margin_start(10)
            inner.set_margin_end(10)
            lbl = Gtk.Label(label=label)
            lbl.set_xalign(0)
            lbl.set_hexpand(True)
            inner.append(lbl)
            if val == current:
                inner.append(Gtk.Image.new_from_icon_name('object-select-symbolic'))
            row = Gtk.ListBoxRow()
            row.set_child(inner)
            lb.append(row)

        def _chosen(_lb, row):
            val = pairs[row.get_index()][0]
            pop.popdown()
            self._apply_change(rule, key, val)

        lb.connect('row-activated', _chosen)
        wrap = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        wrap.set_margin_top(4)
        wrap.set_margin_bottom(4)
        wrap.append(lb)
        pop.set_child(wrap)
        pop.set_parent(anchor)
        pop.set_autohide(True)
        pop.popup()

    # ── Apply change ──────────────────────────────────────────────────────────

    def _apply_change(self, rule: Rule, key: str, new_val: str):
        if key in ('tag', 'group'):
            mk = rule.meta_key
            if new_val:
                self._meta.setdefault(mk, {})[key] = new_val
            else:
                if mk in self._meta:
                    self._meta[mk].pop(key, None)
                    if not any(self._meta[mk].values()):
                        del self._meta[mk]
            _save_meta(self._meta)
            setattr(rule, key, new_val)
            self._rebuild_table()
            return

        old_key  = rule.meta_key
        old_meta = self._meta.get(old_key, {}).copy()
        port      = new_val if key == 'port'      else rule.port
        proto     = new_val if key == 'proto'     else rule.proto
        action    = new_val if key == 'action'    else rule.action
        direction = new_val if key == 'direction' else rule.direction
        comment   = new_val if key == 'comment'   else rule.comment
        new_target = f'{port}/{proto}' if proto else port

        rc, out = self._backend.run('delete', str(rule.num))
        if rc != 0:
            self._show_error('Delete Failed', out)
            return

        args = [action.lower()]
        if direction:
            args.append(direction.lower())
        args.append(new_target)
        if comment:
            args += ['comment', comment]

        rc, out = self._backend.run(*args)
        if rc != 0:
            self._show_error('Add Failed', out)
        else:
            if old_key in self._meta:
                del self._meta[old_key]
            if old_meta:
                self._meta[new_target] = old_meta
            _save_meta(self._meta)
        self._refresh()

    # ── Delete ────────────────────────────────────────────────────────────────

    def _confirm_delete(self, rule: Rule):
        d = Adw.AlertDialog(
            heading=f'Delete  {rule.ufw_target}?',
            body=(rule.comment or f'{rule.action}' +
                  (f' {rule.direction}' if rule.direction else '')) +
                 '\n\nThis cannot be undone.',
        )
        d.add_response('cancel', 'Cancel')
        d.add_response('delete', 'Delete')
        d.set_response_appearance('delete', Adw.ResponseAppearance.DESTRUCTIVE)
        d.set_default_response('cancel')
        d.set_close_response('cancel')
        d.connect('response', self._on_delete_response, rule)
        d.present(self)

    def _on_delete_response(self, _d, response, rule: Rule):
        if response != 'delete':
            return
        rc, out = self._backend.run('delete', str(rule.num))
        if rc == 0:
            mk = rule.meta_key
            if mk in self._meta:
                del self._meta[mk]
                _save_meta(self._meta)
            self._refresh()
        else:
            self._show_error('Delete Failed', out)

    # ── Add rule dialog ───────────────────────────────────────────────────────

    def _on_add_dialog(self, _=None):
        port_e    = Adw.EntryRow(title='Port  (e.g. 22 · 8080 · 8000:9000)')
        comment_e = Adw.EntryRow(title='Comment')
        tag_e     = Adw.EntryRow(title='Tag')
        group_e   = Adw.EntryRow(title='Group')
        proto_r   = Adw.ComboRow(title='Protocol')
        proto_r.set_model(Gtk.StringList.new(['TCP', 'UDP', 'TCP + UDP']))
        dir_r     = Adw.ComboRow(title='Direction')
        dir_r.set_model(Gtk.StringList.new(['In', 'Out', 'Both']))
        action_r  = Adw.ComboRow(title='Action')
        action_r.set_model(Gtk.StringList.new(['Allow', 'Deny', 'Reject']))

        lb = Gtk.ListBox()
        lb.set_selection_mode(Gtk.SelectionMode.NONE)
        lb.add_css_class('boxed-list')
        for w in [port_e, proto_r, dir_r, action_r, comment_e, tag_e, group_e]:
            lb.append(w)

        wrap = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        wrap.set_margin_top(12)
        wrap.set_margin_bottom(4)
        wrap.set_margin_start(4)
        wrap.set_margin_end(4)
        wrap.set_size_request(360, -1)
        wrap.append(lb)

        dlg = Adw.AlertDialog(heading='Add Rule', extra_child=wrap)
        dlg.add_response('cancel', 'Cancel')
        dlg.add_response('add', 'Add')
        dlg.set_response_appearance('add', Adw.ResponseAppearance.SUGGESTED)
        dlg.set_default_response('add')
        dlg.set_close_response('cancel')
        dlg.connect('response', self._on_add_response,
                    port_e, proto_r, dir_r, action_r, comment_e, tag_e, group_e)
        dlg.present(self)

    def _on_add_response(self, _dlg, response,
                          port_e, proto_r, dir_r, action_r, comment_e, tag_e, group_e):
        if response != 'add':
            return
        port = port_e.get_text().strip()
        if not port:
            return
        proto   = ['tcp', 'udp', ''][proto_r.get_selected()]
        direc   = ['in', 'out', ''][dir_r.get_selected()]
        action  = ['allow', 'deny', 'reject'][action_r.get_selected()]
        comment = comment_e.get_text().strip()
        tag     = tag_e.get_text().strip()
        group   = group_e.get_text().strip()
        target  = f'{port}/{proto}' if proto else port

        args = [action]
        if direc:
            args.append(direc)
        args.append(target)
        if comment:
            args += ['comment', comment]

        rc, out = self._backend.run(*args)
        if rc == 0:
            if tag or group:
                self._meta[target] = {'tag': tag, 'group': group}
                _save_meta(self._meta)
            self._refresh()
        else:
            self._show_error('Failed to Add Rule', out)

    # ── Sort popover ──────────────────────────────────────────────────────────

    def _build_sort_popover(self) -> Gtk.Popover:
        opts = [('Port  ↑', 'port', True), ('Port  ↓', 'port', False),
                ('Comment  ↑', 'comment', True), ('Comment  ↓', 'comment', False)]
        lb  = Gtk.ListBox()
        lb.set_selection_mode(Gtk.SelectionMode.NONE)
        lb.add_css_class('boxed-list')
        pop = Gtk.Popover()
        for label, _, _ in opts:
            lbl = Gtk.Label(label=label)
            lbl.set_xalign(0)
            lbl.set_margin_top(6)
            lbl.set_margin_bottom(6)
            lbl.set_margin_start(10)
            lbl.set_margin_end(10)
            row = Gtk.ListBoxRow()
            row.set_child(lbl)
            lb.append(row)

        def _chosen(_lb, row):
            _, key, asc = opts[row.get_index()]
            self._sort_key = key
            self._sort_asc = asc
            self._sort_menu.set_icon_name(
                'view-sort-ascending-symbolic' if asc else 'view-sort-descending-symbolic')
            pop.popdown()
            self._rebuild_table()

        lb.connect('row-activated', _chosen)
        wrap = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        wrap.set_margin_top(4)
        wrap.set_margin_bottom(4)
        wrap.append(lb)
        pop.set_child(wrap)
        return pop

    # ── Tag filter popover ────────────────────────────────────────────────────

    def _build_filter_popover(self) -> Gtk.Popover:
        self._filter_lb = Gtk.ListBox()
        self._filter_lb.set_selection_mode(Gtk.SelectionMode.NONE)
        self._filter_lb.add_css_class('boxed-list')
        self._filter_lb.connect('row-activated', self._on_filter_chosen)
        wrap = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        wrap.set_margin_top(4)
        wrap.set_margin_bottom(4)
        wrap.append(self._filter_lb)
        pop = Gtk.Popover()
        pop.set_child(wrap)
        return pop

    def _update_tag_filter_list(self):
        while (ch := self._filter_lb.get_first_child()):
            self._filter_lb.remove(ch)
        tags = sorted({r.tag for r in self._rules if r.tag})
        for label in ['All tags'] + [f'#{t}' for t in tags]:
            lbl = Gtk.Label(label=label)
            lbl.set_xalign(0)
            lbl.set_margin_top(6)
            lbl.set_margin_bottom(6)
            lbl.set_margin_start(10)
            lbl.set_margin_end(10)
            row = Gtk.ListBoxRow()
            row.set_child(lbl)
            self._filter_lb.append(row)

    def _on_filter_chosen(self, _lb, row):
        tags = sorted({r.tag for r in self._rules if r.tag})
        idx  = row.get_index()
        if idx == 0:
            self._filter_tag = ''
            self._filter_menu.set_label('All tags')
        else:
            self._filter_tag = tags[idx - 1]
            self._filter_menu.set_label(f'#{self._filter_tag}')
        self._filter_popover.popdown()
        self._rebuild_table()

    # ── Group toggle ──────────────────────────────────────────────────────────

    def _on_group_toggled(self, btn: Gtk.ToggleButton):
        self._group_view = btn.get_active()
        btn.set_icon_name('view-paged-symbolic' if self._group_view else 'view-list-symbolic')
        self._rebuild_table()

    # ── UFW toggle ────────────────────────────────────────────────────────────

    def _on_toggle_ufw(self, _btn):
        rc, out = self._backend.run('disable' if self._ufw_active else 'enable')
        if rc == 0:
            self._refresh()
        else:
            self._show_error('UFW Toggle Failed', out)

    # ── Keyboard ──────────────────────────────────────────────────────────────

    def _on_key(self, _ctrl, keyval, _code, state):
        if keyval == Gdk.KEY_n and (state & Gdk.ModifierType.CONTROL_MASK):
            self._on_add_dialog()
            return True
        return False

    # ── Error ─────────────────────────────────────────────────────────────────

    def _show_error(self, heading: str, body: str):
        d = Adw.AlertDialog(heading=heading, body=body or '(no details)')
        d.add_response('ok', 'OK')
        d.present(self)


# ── Application ───────────────────────────────────────────────────────────────

class UfwApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id='com.vutureland.ufw')
        self.connect('activate', self._on_activate)

    def _on_activate(self, _app):
        display = Gdk.Display.get_default()
        for path in (_CSS_COLORS if os.path.exists(_CSS_COLORS) else _CSS_COLORS_FB, _CSS_BASE):
            if os.path.exists(path):
                p = Gtk.CssProvider()
                p.load_from_path(path)
                Gtk.StyleContext.add_provider_for_display(
                    display, p, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        UfwManagerWindow(application=self).present()


if __name__ == '__main__':
    UfwApp().run(sys.argv)
