"""NotifyWindow — layer-shell overlay that stacks notification popups.

Position, style, and margins are read from notify_config on startup.
"""

from __future__ import annotations

import sys, os
sys.path.insert(0, os.path.dirname(__file__))

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Gtk4LayerShell', '1.0')
from gi.repository import Gtk, GLib, Gtk4LayerShell

import notify_config
from notify_popup import NotifPopup

# Slide-in / out animation duration (ms)
_ANIM_MS = 200

# Map config position string → (anchor_left, anchor_right, anchor_top, anchor_bottom)
_ANCHOR_MAP: dict[str, tuple[bool, bool, bool, bool]] = {
    'top-left':      (True,  False, True,  False),
    'top-center':    (False, False, True,  False),
    'top-right':     (False, True,  True,  False),
    'center-left':   (True,  False, False, False),
    'center-right':  (False, True,  False, False),
    'bottom-left':   (True,  False, False, True),
    'bottom-center': (False, False, False, True),
    'bottom-right':  (False, True,  False, True),
}

# Alignment for the card stack within the window
_HALIGN_MAP: dict[str, Gtk.Align] = {
    'top-left':      Gtk.Align.START,  'center-left':   Gtk.Align.START,
    'bottom-left':   Gtk.Align.START,
    'top-center':    Gtk.Align.CENTER, 'bottom-center': Gtk.Align.CENTER,
    'top-right':     Gtk.Align.END,    'center-right':  Gtk.Align.END,
    'bottom-right':  Gtk.Align.END,
}
_VALIGN_MAP: dict[str, Gtk.Align] = {
    'top-left':      Gtk.Align.START, 'top-center':    Gtk.Align.START,
    'top-right':     Gtk.Align.START,
    'center-left':   Gtk.Align.CENTER, 'center-right': Gtk.Align.CENTER,
    'bottom-left':   Gtk.Align.END,   'bottom-center': Gtk.Align.END,
    'bottom-right':  Gtk.Align.END,
}

# Positions where new cards should be appended (not prepended) so the newest
# card ends up closest to the anchor edge.
_APPEND_POSITIONS = {'bottom-left', 'bottom-center', 'bottom-right'}


class NotifyWindow:
    """Manages the layer-shell window that holds stacked notification cards."""

    def __init__(self, app):
        cfg = notify_config.load()
        self._cfg = cfg

        pos      = cfg.get('notify_position', 'top-right')
        margin   = cfg.get('notify_margin_px', 12)
        width    = cfg.get('notify_width_px',  380)
        max_pop  = cfg.get('notify_max_popups',  5)
        order    = cfg.get('notify_stack_order', 'newest_top')
        self._overlap_px = max(0, cfg.get('notify_overlap_px', 5))

        self._max_popups = max_pop
        self._append_new = (order == 'newest_bottom') or (pos in _APPEND_POSITIONS)

        self._win = Gtk.ApplicationWindow(application=app)
        self._win.set_title('Vutureland Notifications')
        self._win.set_decorated(False)

        anchors = _ANCHOR_MAP.get(pos, (False, True, True, False))

        style  = cfg.get('notify_style', 'float')
        left, right, top, bottom = anchors

        self._stack = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        # In dock mode the anchored edges get 0 margin so cards sit flush.
        self._stack.set_margin_top(    0 if (style == 'dock' and top)    else margin)
        self._stack.set_margin_bottom( 0 if (style == 'dock' and bottom) else margin)
        self._stack.set_margin_start(  0 if (style == 'dock' and left)   else margin)
        self._stack.set_margin_end(    0 if (style == 'dock' and right)  else margin)
        self._stack.set_valign(_VALIGN_MAP.get(pos, Gtk.Align.START))
        self._stack.set_halign(_HALIGN_MAP.get(pos, Gtk.Align.END))
        self._stack.set_size_request(width, -1)

        self._win.set_child(self._stack)

        # {nid: (NotifPopup, Gtk.Revealer)}
        self._entries: dict[int, tuple[NotifPopup, Gtk.Revealer]] = {}

        self._setup_layer_shell(anchors, margin, style)

    # ── Layer-shell setup ─────────────────────────────────────────────────────

    def _setup_layer_shell(
        self,
        anchors: tuple[bool, bool, bool, bool],
        margin: int,
        style: str,
    ) -> None:
        win  = self._win
        left, right, top, bottom = anchors

        Gtk4LayerShell.init_for_window(win)
        Gtk4LayerShell.set_namespace(win, 'vutureland-notify')
        Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.OVERLAY)

        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.LEFT,   left)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.RIGHT,  right)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.TOP,    top)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.BOTTOM, bottom)

        # Float style: push cards inward by margin on the anchored edges.
        # Dock style: flush to screen edges, margin stays 0.
        m = margin if style == 'float' else 0
        if left:   Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.LEFT,   m)
        if right:  Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.RIGHT,  m)
        if top:    Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.TOP,    m)
        if bottom: Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.BOTTOM, m)

        # No keyboard grab; other apps keep their focus
        Gtk4LayerShell.set_keyboard_mode(win, Gtk4LayerShell.KeyboardMode.NONE)
        # Don't push waybar out of the way
        Gtk4LayerShell.set_exclusive_zone(win, 0)

    # ── Public API ────────────────────────────────────────────────────────────

    def add_popup(self, popup: NotifPopup) -> None:
        """Slide a new notification in."""
        if len(self._entries) >= self._max_popups:
            oldest_nid = next(iter(self._entries))
            self.remove_popup(oldest_nid)

        revealer = Gtk.Revealer()
        revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        revealer.set_transition_duration(_ANIM_MS)
        revealer.set_reveal_child(False)
        revealer.set_child(popup)

        if self._append_new:
            # New card at bottom: pull it up into the one above
            if self._entries:
                revealer.set_margin_top(-self._overlap_px)
            self._stack.append(revealer)
        else:
            # New card at top: push the card below up into this one
            revealer.set_margin_bottom(-self._overlap_px)
            self._stack.prepend(revealer)

        self._entries[popup.nid] = (popup, revealer)
        self._win.present()
        GLib.idle_add(lambda: (revealer.set_reveal_child(True), False)[1])

    def remove_popup(self, nid: int) -> None:
        """Animate the notification out and remove it."""
        entry = self._entries.pop(nid, None)
        if entry is None:
            return
        popup, revealer = entry
        popup.cancel_timer()

        def _on_revealed(rev, _pspec):
            if not rev.get_child_revealed():
                self._stack.remove(rev)
                if not self._entries:
                    self._win.hide()

        revealer.connect('notify::child-revealed', _on_revealed)
        revealer.set_reveal_child(False)

    def replace_popup(self, old_nid: int, new_popup: NotifPopup) -> None:
        """Replace an existing notification in-place (for replaces_id)."""
        entry = self._entries.pop(old_nid, None)
        if entry is None:
            self.add_popup(new_popup)
            return
        old_popup, revealer = entry
        old_popup.cancel_timer()
        revealer.set_child(new_popup)
        self._entries[new_popup.nid] = (new_popup, revealer)
        if not revealer.get_child_revealed():
            GLib.idle_add(lambda: (revealer.set_reveal_child(True), False)[1])
