"""NotifPopup — single notification card widget."""

from __future__ import annotations
import os

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('GdkPixbuf', '2.0')
from gi.repository import Gtk, Gdk, GLib, GdkPixbuf

# Reason codes (freedesktop spec §8.2)
REASON_EXPIRED   = 1
REASON_DISMISSED = 2
REASON_CLOSED    = 3

_DEFAULT_TIMEOUT_MS  = 5_000
_CRITICAL_TIMEOUT_MS = 0      # never auto-dismiss


class NotifPopup(Gtk.Box):
    """One notification card.

    on_close(nid, reason) — called when the notification should be removed.
    on_action(nid, key)   — called when an action button is activated.
    """

    def __init__(
        self,
        nid:            int,
        app_name:       str,
        app_icon:       str,
        summary:        str,
        body:           str,
        actions:        list[str],
        hints:          dict,
        timeout_ms:     int,
        # behavior flags (from notify_config)
        show_icons:     bool       = True,
        show_app_name:  bool       = True,
        click_action:   str        = 'dismiss',   # 'dismiss' | 'action' | 'none'
        dock_edge:      str | None = None,         # 'top'|'bottom'|'left'|'right' or None
        on_close        = None,
        on_action       = None,
    ):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.nid         = nid
        self._on_close   = on_close
        self._on_action  = on_action
        self._click_action = click_action
        self._actions    = actions   # keep for default-action lookup
        self._timer_id: int | None = None

        urgency = int(hints.get('urgency', 1))
        self.add_css_class('notif-card')
        if urgency == 0:
            self.add_css_class('urgency-low')
        elif urgency == 2:
            self.add_css_class('urgency-critical')
        if dock_edge:
            self.add_css_class(f'notif-dock-{dock_edge}')

        self._build_header(app_name, app_icon, hints, show_icons, show_app_name)
        self._build_body(app_icon, hints, summary, body, show_icons)
        self._build_actions(actions)
        self._attach_click()
        self._start_timer(urgency, timeout_ms)

    # ── Layout ────────────────────────────────────────────────────────────────

    def _build_header(
        self,
        app_name:     str,
        app_icon:     str,
        hints:        dict,
        show_icons:   bool,
        show_app_name: bool,
    ) -> None:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        row.set_margin_start(12)
        row.set_margin_end(8)
        row.set_margin_top(10)
        row.set_margin_bottom(2)

        if show_icons:
            icon = _load_icon(app_icon, hints, size=16)
            if icon:
                row.append(icon)

        if show_app_name:
            lbl = Gtk.Label(label=app_name or 'Notification')
            lbl.add_css_class('notif-app-name')
            lbl.set_xalign(0)
            lbl.set_hexpand(True)
            lbl.set_ellipsize(3)   # PANGO_ELLIPSIZE_END
            row.append(lbl)
        else:
            spacer = Gtk.Box()
            spacer.set_hexpand(True)
            row.append(spacer)

        close_btn = Gtk.Button()
        close_btn.set_icon_name('window-close-symbolic')
        close_btn.add_css_class('flat')
        close_btn.add_css_class('circular')
        close_btn.set_valign(Gtk.Align.CENTER)
        close_btn.connect('clicked', lambda _: self._dismiss(REASON_DISMISSED))
        row.append(close_btn)

        self.append(row)

    def _build_body(
        self,
        app_icon:   str,
        hints:      dict,
        summary:    str,
        body:       str,
        show_icons: bool,
    ) -> None:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.set_margin_start(12)
        row.set_margin_end(12)
        row.set_margin_top(4)
        row.set_margin_bottom(10)

        if show_icons:
            large_icon = _load_icon(app_icon, hints, size=42)
            if large_icon:
                large_icon.set_valign(Gtk.Align.START)
                row.append(large_icon)

        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        texts.set_hexpand(True)

        if summary:
            s = Gtk.Label(label=summary)
            s.add_css_class('notif-summary')
            s.set_xalign(0)
            s.set_wrap(True)
            s.set_max_width_chars(42)
            texts.append(s)

        if body:
            b = Gtk.Label()
            b.add_css_class('notif-body')
            b.set_xalign(0)
            b.set_wrap(True)
            b.set_max_width_chars(42)
            b.set_use_markup(True)
            try:
                b.set_label(body)
            except Exception:
                b.set_use_markup(False)
                b.set_text(body)
            texts.append(b)

        row.append(texts)
        self.append(row)

    def _build_actions(self, actions: list[str]) -> None:
        pairs = [(actions[i], actions[i + 1]) for i in range(0, len(actions) - 1, 2)
                 if actions[i] != 'default']
        if not pairs:
            return

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        row.set_margin_start(12)
        row.set_margin_end(12)
        row.set_margin_bottom(10)
        for key, label in pairs:
            btn = Gtk.Button(label=label)
            btn.add_css_class('pill')
            btn.connect('clicked', lambda _, k=key: self._invoke_action(k))
            row.append(btn)
        self.append(row)

    def _attach_click(self) -> None:
        gesture = Gtk.GestureClick.new()
        gesture.connect('pressed', self._on_body_click)
        self.add_controller(gesture)

    # ── Timer ─────────────────────────────────────────────────────────────────

    def _start_timer(self, urgency: int, timeout_ms: int) -> None:
        if urgency == 2:
            ms = _CRITICAL_TIMEOUT_MS
        elif timeout_ms < 0:
            ms = _DEFAULT_TIMEOUT_MS
        else:
            ms = timeout_ms

        if ms > 0:
            self._timer_id = GLib.timeout_add(ms, self._on_timeout)

    def _on_timeout(self) -> bool:
        self._timer_id = None
        self._dismiss(REASON_EXPIRED)
        return GLib.SOURCE_REMOVE

    def cancel_timer(self) -> None:
        if self._timer_id is not None:
            GLib.source_remove(self._timer_id)
            self._timer_id = None

    # ── Interaction ───────────────────────────────────────────────────────────

    def _dismiss(self, reason: int) -> None:
        self.cancel_timer()
        if self._on_close:
            self._on_close(self.nid, reason)

    def _invoke_action(self, key: str) -> None:
        self.cancel_timer()
        if self._on_action:
            self._on_action(self.nid, key)
        if self._on_close:
            self._on_close(self.nid, REASON_DISMISSED)

    def _on_body_click(self, _gesture, _n, _x, _y) -> None:
        if self._click_action == 'none':
            return
        if self._click_action == 'action':
            # Find the 'default' action key if present
            actions = self._actions
            default_key = next(
                (actions[i] for i in range(0, len(actions) - 1, 2)
                 if actions[i] == 'default'),
                None,
            )
            if default_key is not None:
                self._invoke_action(default_key)
                return
        # 'dismiss' or no default action found
        self._dismiss(REASON_DISMISSED)


# ── Icon helpers ──────────────────────────────────────────────────────────────

def _load_icon(icon_name: str, hints: dict, size: int) -> Gtk.Image | None:
    """Try image-data hint → image-path hint → icon_name (theme or file path)."""
    pb = _pixbuf_from_hints(hints, size)
    if pb:
        img = Gtk.Image.new_from_pixbuf(pb)
        img.set_pixel_size(size)
        return img

    if icon_name:
        if os.path.isabs(icon_name) and os.path.exists(icon_name):
            try:
                pb = GdkPixbuf.Pixbuf.new_from_file_at_size(icon_name, size, size)
                return Gtk.Image.new_from_pixbuf(pb)
            except Exception:
                pass
        else:
            theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default())
            if theme.has_icon(icon_name):
                img = Gtk.Image.new_from_icon_name(icon_name)
                img.set_pixel_size(size)
                return img

    return None


def _pixbuf_from_hints(hints: dict, size: int) -> GdkPixbuf.Pixbuf | None:
    if 'image-data' in hints:
        try:
            w, h, rowstride, has_alpha, bps, _ch, raw = hints['image-data']
            pb = GdkPixbuf.Pixbuf.new_from_bytes(
                GLib.Bytes.new(bytes(raw)),
                GdkPixbuf.Colorspace.RGB,
                has_alpha, bps, w, h, rowstride,
            )
            if size:
                pb = pb.scale_simple(size, size, GdkPixbuf.InterpType.BILINEAR)
            return pb
        except Exception:
            pass

    if 'image-path' in hints:
        path = str(hints['image-path'])
        if os.path.exists(path):
            try:
                return GdkPixbuf.Pixbuf.new_from_file_at_size(path, size, size)
            except Exception:
                pass

    return None
