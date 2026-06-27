"""MPris media player card — album art as fullbleed background."""
from __future__ import annotations
import gi, threading, urllib.request, tempfile, os
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, Gio, GLib, GdkPixbuf, Gdk

_REFRESH_MS = 2000


# ── D-Bus helpers (worker thread) ─────────────────────────────────────────────

def _list_players() -> list[str]:
    try:
        proxy = Gio.DBusProxy.new_for_bus_sync(
            Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, None,
            'org.freedesktop.DBus', '/org/freedesktop/DBus',
            'org.freedesktop.DBus', None,
        )
        names = proxy.call_sync('ListNames', None, Gio.DBusCallFlags.NONE, 1000, None)
        return sorted(n for n in names.unpack()[0]
                      if n.startswith('org.mpris.MediaPlayer2.'))
    except Exception:
        return []


def _make_proxy(bus: str) -> Gio.DBusProxy | None:
    try:
        return Gio.DBusProxy.new_for_bus_sync(
            Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, None,
            bus, '/org/mpris/MediaPlayer2',
            'org.mpris.MediaPlayer2.Player', None,
        )
    except Exception:
        return None


def _fetch_state(bus: str) -> dict:
    proxy = _make_proxy(bus)
    if not proxy:
        return {}
    out: dict = {}
    try:
        sv = proxy.get_cached_property('PlaybackStatus')
        out['status'] = sv.unpack() if sv else 'Stopped'
    except Exception:
        out['status'] = 'Stopped'
    try:
        mv = proxy.get_cached_property('Metadata')
        if mv:
            meta = mv.unpack()
            out['title']   = str(meta.get('xesam:title', '') or '')
            artists        = meta.get('xesam:artist', []) or []
            out['artist']  = ', '.join(str(a) for a in artists) if artists else \
                             str(meta.get('xesam:albumArtist', '') or '')
            out['art_url'] = (str(meta.get('mpris:artUrl', '') or '') or
                              str(meta.get('xesam:artUrl', '') or ''))
    except Exception:
        pass
    return out


def _find_active_player() -> tuple[str | None, dict]:
    """Return (bus, state) for the best active player.

    Priority: Playing > Paused. Stopped players are ignored so browsers
    that register an idle MPRIS session don't show up."""
    players = _list_players()
    paused: tuple[str, dict] | None = None
    for bus in players:
        state = _fetch_state(bus)
        status = state.get('status', 'Stopped')
        if status == 'Playing':
            return bus, state
        if status == 'Paused' and paused is None:
            paused = (bus, state)
    if paused:
        return paused
    return None, {}


# ── Widget ────────────────────────────────────────────────────────────────────

class PlayerWidget(Adw.PreferencesGroup):
    def __init__(self):
        super().__init__()
        self._current_bus: str | None = None
        self._art_url: str | None = None
        self._build()
        threading.Thread(target=self._bg_refresh, daemon=True).start()
        GLib.timeout_add(_REFRESH_MS, self._schedule)

    # ── Build ─────────────────────────────────────────────────────────────────

    def _build(self):
        self._row = Adw.PreferencesRow()
        self._row.set_activatable(False)
        self._row.set_overflow(Gtk.Overflow.HIDDEN)
        self._row.add_css_class('player-card')

        # Overlay: bg picture → scrim → content
        card = Gtk.Overlay()
        card.set_hexpand(True)
        card.set_vexpand(True)

        # Background art; size_request(-1,1) stops the image's natural size
        # from inflating the row — CSS max-height on .player-card caps the height.
        self._bg = Gtk.Picture()
        self._bg.set_content_fit(Gtk.ContentFit.COVER)
        self._bg.set_hexpand(True)
        self._bg.set_vexpand(True)
        self._bg.set_size_request(-1, 1)
        card.set_child(self._bg)

        scrim = Gtk.Box()
        scrim.add_css_class('player-scrim')
        scrim.set_hexpand(True)
        scrim.set_vexpand(True)
        card.add_overlay(scrim)

        # Content: title/artist left, controls right
        content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        content.set_hexpand(True)
        content.set_vexpand(True)
        content.set_margin_top(12)
        content.set_margin_bottom(12)
        content.set_margin_start(16)
        content.set_margin_end(12)
        card.add_overlay(content)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        text.set_valign(Gtk.Align.CENTER)
        text.set_hexpand(True)

        self._title = Gtk.Label(label='Kein Player aktiv')
        self._title.set_xalign(0.0)
        self._title.set_ellipsize(3)
        self._title.add_css_class('player-title')

        self._artist = Gtk.Label(label='')
        self._artist.set_xalign(0.0)
        self._artist.set_ellipsize(3)
        self._artist.add_css_class('player-artist')

        text.append(self._title)
        text.append(self._artist)
        content.append(text)

        ctrl = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        ctrl.set_valign(Gtk.Align.CENTER)

        for icon, method in [
            ('media-skip-backward-symbolic',  'Previous'),
            ('media-playback-start-symbolic', 'PlayPause'),
            ('media-skip-forward-symbolic',   'Next'),
        ]:
            btn = Gtk.Button(icon_name=icon)
            btn.add_css_class('circular')
            btn.add_css_class('player-btn')
            btn.connect('clicked', lambda _, m=method: self._control(m))
            if method == 'PlayPause':
                self._play_btn = btn
            ctrl.append(btn)

        content.append(ctrl)
        self._row.set_child(card)
        self.add(self._row)

    # ── Refresh loop ─────────────────────────────────────────────────────────

    def _schedule(self) -> bool:
        threading.Thread(target=self._bg_refresh, daemon=True).start()
        return GLib.SOURCE_CONTINUE

    def _bg_refresh(self):
        bus, state = _find_active_player()
        GLib.idle_add(self._apply, bus, state)

    # ── Apply ─────────────────────────────────────────────────────────────────

    def _apply(self, bus: str | None, state: dict):
        if bus != self._current_bus:
            self._current_bus = bus
            self._art_url = None

        if not bus:
            self._title.set_label('Kein Player aktiv')
            self._artist.set_label('')
            self._play_btn.set_icon_name('media-playback-start-symbolic')
            self._bg.set_paintable(None)
            return

        playing = state.get('status') == 'Playing'
        self._play_btn.set_icon_name(
            'media-playback-pause-symbolic' if playing
            else 'media-playback-start-symbolic'
        )

        title = state.get('title') or ''
        if not title:
            raw   = bus.replace('org.mpris.MediaPlayer2.', '').split('.')[0]
            title = raw.capitalize() if raw else 'Player'
        self._title.set_label(title)
        self._artist.set_label(state.get('artist') or '')

        art_url = state.get('art_url', '')
        if art_url != self._art_url:
            self._art_url = art_url
            self._load_art(art_url)

    # ── Art loading ───────────────────────────────────────────────────────────

    def _load_art(self, url: str):
        if not url:
            GLib.idle_add(self._bg.set_paintable, None)
            return
        if url.startswith('file://'):
            threading.Thread(target=self._set_art, args=(url[7:],),
                             daemon=True).start()
        elif url.startswith('http'):
            def _fetch():
                try:
                    with urllib.request.urlopen(url, timeout=3) as r:
                        data = r.read()
                    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
                    tmp.write(data); tmp.close()
                    self._set_art(tmp.name)
                except Exception:
                    GLib.idle_add(self._bg.set_paintable, None)
            threading.Thread(target=_fetch, daemon=True).start()

    def _set_art(self, path: str):
        try:
            pb  = GdkPixbuf.Pixbuf.new_from_file(path)
            tex = Gdk.Texture.new_for_pixbuf(pb)
            GLib.idle_add(self._bg.set_paintable, tex)
        except Exception:
            GLib.idle_add(self._bg.set_paintable, None)

    # ── Controls ──────────────────────────────────────────────────────────────

    def _control(self, method: str):
        if not self._current_bus:
            return
        bus = self._current_bus
        def _call():
            # Always create a fresh proxy to avoid stale-connection issues
            proxy = _make_proxy(bus)
            if proxy:
                try:
                    proxy.call_sync(method, None, Gio.DBusCallFlags.NONE, 1000, None)
                except Exception:
                    pass
            GLib.timeout_add(300, lambda: (
                threading.Thread(target=self._bg_refresh, daemon=True).start(),
                False)[1])
        threading.Thread(target=_call, daemon=True).start()
