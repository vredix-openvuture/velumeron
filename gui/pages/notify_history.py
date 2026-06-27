from __future__ import annotations
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw

import os, json, re, time


def _user_dir() -> str:
    return os.environ.get('VUTURELAND_USER_DIR') or os.path.join(
        os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config')),
        'vutureland')


_HISTORY_FILE = os.path.join(_user_dir(), 'gui', 'notify-history.json')


def _rel_time(ts: float) -> str:
    diff = time.time() - ts
    if diff < 60:    return 'gerade eben'
    if diff < 3600:  return f'vor {int(diff // 60)} Min.'
    if diff < 86400: return f'vor {int(diff // 3600)} Std.'
    return f'vor {int(diff // 86400)} T.'


class NotifyHistoryPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__()
        self._rows: list[Gtk.Widget] = []
        self._group: Adw.PreferencesGroup | None = None
        self._home_cb = None
        self._build_ui()
        self.connect('map', lambda _: self._reload())

    def set_home_callback(self, cb):
        self._home_cb = cb

    # ── Build ────────────────────────────────────────────────────────────────

    def _build_back_group(self) -> Adw.PreferencesGroup:
        img = Gtk.Image.new_from_icon_name('go-up-symbolic')
        img.set_halign(Gtk.Align.CENTER)
        img.set_hexpand(True)

        row = Adw.PreferencesRow()
        row.set_activatable(False)
        row.add_css_class('back-btn-row')
        row.set_child(img)
        gesture = Gtk.GestureClick()
        gesture.connect('released', lambda g, n, x, y: self._home_cb and self._home_cb())
        row.add_controller(gesture)

        group = Adw.PreferencesGroup()
        group.add_css_class('back-btn-group')
        group.add(row)
        return group

    def _build_ui(self):
        self.add(self._build_back_group())

        group = Adw.PreferencesGroup(title='Benachrichtigungen')

        clear_btn = Gtk.Button(label='Alle löschen')
        clear_btn.add_css_class('flat')
        clear_btn.add_css_class('pill')
        clear_btn.set_valign(Gtk.Align.CENTER)
        clear_btn.connect('clicked', self._on_clear)
        group.set_header_suffix(clear_btn)

        self._group = group
        self.add(group)

        # Empty state — transparent, large, centered
        lbl = Gtk.Label(label='Keine Benachrichtigungen')
        lbl.add_css_class('dim-label')
        lbl.add_css_class('notify-empty-label')
        lbl.set_halign(Gtk.Align.CENTER)
        lbl.set_valign(Gtk.Align.CENTER)
        self._empty_label = lbl

        empty_row = Adw.PreferencesRow()
        empty_row.set_activatable(False)
        empty_row.add_css_class('flat')
        empty_row.add_css_class('notify-empty-row')
        empty_row.set_child(lbl)

        empty_group = Adw.PreferencesGroup()
        empty_group.add_css_class('back-btn-group')
        empty_group.add(empty_row)
        self._empty_group = empty_group
        self.add(empty_group)

        self._reload()

    # ── Load / reload ────────────────────────────────────────────────────────

    def _reload(self):
        if self._group is None:
            return

        for w in self._rows:
            self._group.remove(w)
        self._rows.clear()

        history: list[dict] = []
        try:
            with open(_HISTORY_FILE) as f:
                history = json.load(f)
        except Exception:
            pass

        self._empty_group.set_visible(not history)
        self._group.set_visible(bool(history))

        if not history:
            return

        # Group by app_name, preserve newest-first order per group
        by_app: dict[str, list[dict]] = {}
        for entry in history[:60]:
            key = entry.get('app_name', '') or ''
            by_app.setdefault(key, []).append(entry)

        # Sort app-groups by their most-recent entry
        sorted_groups = sorted(
            by_app.items(),
            key=lambda kv: float(kv[1][0].get('timestamp', 0)),
            reverse=True,
        )

        for app, entries in sorted_groups:
            if len(entries) == 1:
                row = self._make_row(entries[0])
            else:
                row = self._make_stack_row(app, entries)
            self._group.add(row)
            self._rows.append(row)

    # ── Row builders ─────────────────────────────────────────────────────────

    def _make_stack_row(self, app: str, entries: list[dict]) -> Adw.ExpanderRow:
        latest  = entries[0]
        summary = latest.get('summary', '') or '(kein Titel)'
        ts      = float(latest.get('timestamp', 0))

        expander = Adw.ExpanderRow(title=app or '(unbekannt)')
        sub_parts = [summary]
        if ts:
            sub_parts.append(_rel_time(ts))
        expander.set_subtitle(' · '.join(sub_parts))

        badge = Gtk.Label(label=str(len(entries)))
        badge.add_css_class('notify-badge')
        badge.set_valign(Gtk.Align.CENTER)
        expander.add_prefix(badge)

        for entry in entries:
            expander.add_row(self._make_row(entry, show_app=False))

        return expander

    def _make_row(self, entry: dict, show_app: bool = True) -> Adw.ActionRow:
        summary = entry.get('summary', '') or '(kein Titel)'
        body    = re.sub(r'<[^>]+>', '', entry.get('body', '') or '')
        app     = entry.get('app_name', '') or ''
        ts      = float(entry.get('timestamp', 0))
        urgency = int(entry.get('urgency', 1))

        row = Adw.ActionRow(title=summary)
        if body:
            row.set_subtitle(body)
            row.set_subtitle_lines(2)
        row.set_activatable(False)

        if urgency != 1:
            color = '#e01b24' if urgency >= 2 else '#a0a0a0'
            dot = Gtk.Label()
            dot.set_use_markup(True)
            dot.set_markup(f'<span foreground="{color}">●</span>')
            dot.set_valign(Gtk.Align.CENTER)
            row.add_prefix(dot)

        parts = [p for p in ((app if show_app else ''), _rel_time(ts) if ts else '') if p]
        if parts:
            meta = Gtk.Label(label=' · '.join(parts))
            meta.add_css_class('dim-label')
            meta.add_css_class('caption')
            meta.set_valign(Gtk.Align.CENTER)
            row.add_suffix(meta)

        return row

    # ── Handlers ─────────────────────────────────────────────────────────────

    def _on_clear(self, _):
        try:
            with open(_HISTORY_FILE, 'w') as f:
                json.dump([], f)
        except Exception:
            pass
        self._reload()
