#!/usr/bin/env python3
"""Vutureland Notification Daemon — org.freedesktop.Notifications D-Bus service.

Usage (via main.py):
    python3 main.py --notify              # start daemon
    python3 main.py --notify --daemon     # start hidden (background)
    python3 main.py --notify --end        # stop running daemon
"""

import os, sys, signal, atexit, json, time as _time

# ── LD_PRELOAD / GTK backend (must happen before any GTK import) ─────────────
_LIB = '/usr/lib/libgtk4-layer-shell.so'
if 'libgtk4-layer-shell' not in os.environ.get('LD_PRELOAD', ''):
    os.environ['LD_PRELOAD'] = _LIB + ':' + os.environ.get('LD_PRELOAD', '')
    os.execv(sys.executable, [sys.executable] + sys.argv)

os.environ['GDK_BACKEND'] = 'wayland'

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
gi.require_version('Gtk4LayerShell', '1.0')
from gi.repository import Gtk, Adw, Gdk, Gio, GLib

sys.path.insert(0, os.path.dirname(__file__))
from notify_popup  import NotifPopup, REASON_CLOSED, REASON_DISMISSED
from notify_window import NotifyWindow
import notify_config

# ── PID management ────────────────────────────────────────────────────────────
_PID_FILE = '/tmp/vutureland-notify.pid'


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _running_pid() -> int | None:
    try:
        pid = int(open(_PID_FILE).read().strip())
        return pid if _pid_alive(pid) else None
    except (OSError, ValueError):
        return None


def _acquire_pid_lock() -> bool:
    if _running_pid() is not None:
        return False
    with open(_PID_FILE, 'w') as f:
        f.write(str(os.getpid()))
    atexit.register(lambda: os.unlink(_PID_FILE) if os.path.exists(_PID_FILE) else None)
    return True


# ── D-Bus interface XML ───────────────────────────────────────────────────────
_DBUS_XML = """
<node>
  <interface name='org.freedesktop.Notifications'>
    <method name='GetCapabilities'>
      <arg type='as'    name='capabilities'  direction='out'/>
    </method>
    <method name='Notify'>
      <arg type='s'     name='app_name'      direction='in'/>
      <arg type='u'     name='replaces_id'   direction='in'/>
      <arg type='s'     name='app_icon'      direction='in'/>
      <arg type='s'     name='summary'       direction='in'/>
      <arg type='s'     name='body'          direction='in'/>
      <arg type='as'    name='actions'       direction='in'/>
      <arg type='a{sv}' name='hints'         direction='in'/>
      <arg type='i'     name='expire_timeout' direction='in'/>
      <arg type='u'     name='id'            direction='out'/>
    </method>
    <method name='CloseNotification'>
      <arg type='u' name='id' direction='in'/>
    </method>
    <method name='GetServerInformation'>
      <arg type='s' name='name'         direction='out'/>
      <arg type='s' name='vendor'       direction='out'/>
      <arg type='s' name='version'      direction='out'/>
      <arg type='s' name='spec_version' direction='out'/>
    </method>
    <signal name='NotificationClosed'>
      <arg type='u' name='id'/>
      <arg type='u' name='reason'/>
    </signal>
    <signal name='ActionInvoked'>
      <arg type='u' name='id'/>
      <arg type='s' name='action_key'/>
    </signal>
  </interface>
</node>
"""

# ── Notification CSS ──────────────────────────────────────────────────────────
_NOTIFY_CSS = b"""
.notif-card {
    background-color: @window_bg_color;
    border-radius: 14px;
    border: 1px solid @borders;
}
.notif-card.urgency-critical {
    border: 2px solid #e01b24;
}
.notif-card.urgency-low {
    opacity: 0.80;
}
/* Dock mode: flatten the corner(s) and drop the border on the screen-edge side */
.notif-card.notif-dock-top {
    border-top-left-radius: 0;
    border-top-right-radius: 0;
    border-top-color: transparent;
}
.notif-card.notif-dock-bottom {
    border-bottom-left-radius: 0;
    border-bottom-right-radius: 0;
    border-bottom-color: transparent;
}
.notif-card.notif-dock-left {
    border-top-left-radius: 0;
    border-bottom-left-radius: 0;
    border-left-color: transparent;
}
.notif-card.notif-dock-right {
    border-top-right-radius: 0;
    border-bottom-right-radius: 0;
    border-right-color: transparent;
}
.notif-app-name {
    font-size: 0.78em;
    opacity: 0.60;
}
.notif-summary {
    font-weight: 600;
}
.notif-body {
    font-size: 0.9em;
    opacity: 0.85;
}
"""


def _user_dir() -> str:
    xdg = os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config'))
    return os.environ.get('VUTURELAND_USER_DIR', os.path.join(xdg, 'vutureland'))


_HISTORY_FILE = os.path.join(_user_dir(), 'gui', 'notify-history.json')
_MAX_HISTORY  = 100


def _append_history(nid: int, replaces_id: int, app_name: str, app_icon: str,
                    summary: str, body: str, hints: dict) -> None:
    try:
        urgency = hints.get('urgency', 1)
        if hasattr(urgency, 'unpack'):
            urgency = urgency.unpack()
        entry = {
            'id':        nid,
            'app_name':  app_name,
            'app_icon':  app_icon,
            'summary':   summary,
            'body':      body,
            'timestamp': _time.time(),
            'urgency':   int(urgency),
        }
        try:
            with open(_HISTORY_FILE) as f:
                history = json.load(f)
        except Exception:
            history = []
        # Remove superseded entry if this is an update
        if replaces_id > 0:
            history = [e for e in history if e.get('id') != replaces_id]
        history.insert(0, entry)
        history = history[:_MAX_HISTORY]
        os.makedirs(os.path.dirname(_HISTORY_FILE), exist_ok=True)
        with open(_HISTORY_FILE, 'w') as f:
            json.dump(history, f, indent=2)
    except Exception:
        pass


def _pkg_dir() -> str:
    return os.environ.get('VUTURELAND_DIR',
                          os.path.realpath(os.path.join(os.path.dirname(__file__), '..')))


# ── Application ───────────────────────────────────────────────────────────────

class NotifyDaemon(Adw.Application):
    def __init__(self):
        super().__init__(application_id='com.vutureland.notify-daemon',
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self._conn:     Gio.DBusConnection | None = None
        self._reg_id:   int = 0
        self._window:   NotifyWindow | None = None
        self._next_id:  int = 1
        self.connect('activate', self._activate)

    # ── Setup ─────────────────────────────────────────────────────────────────

    def _activate(self, _) -> None:
        display = Gdk.Display.get_default()
        self._load_css(display)

        self._window = NotifyWindow(self)

        Gio.bus_own_name(
            Gio.BusType.SESSION,
            'org.freedesktop.Notifications',
            # REPLACE takes over from swaync or any existing daemon
            Gio.BusNameOwnerFlags.REPLACE,
            self._on_bus_acquired,
            self._on_name_acquired,
            self._on_name_lost,
        )

        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM,
                             lambda: (self.quit(), GLib.SOURCE_REMOVE)[1])

    def _load_css(self, display) -> None:
        # wallust palette
        colors_path = os.path.join(_user_dir(), 'assets', 'colors_gtk.css')
        colors_fallback = os.path.join(_pkg_dir(), 'assets', 'colors_gtk.css')
        colors_prov = Gtk.CssProvider()
        src = colors_path if os.path.exists(colors_path) else colors_fallback
        if os.path.exists(src):
            colors_prov.load_from_path(src)
        Gtk.StyleContext.add_provider_for_display(
            display, colors_prov, Gtk.STYLE_PROVIDER_PRIORITY_USER)

        # base style.css (for shared classes like .pill, .module-chip, etc.)
        base_css = os.path.join(os.path.dirname(__file__), 'style.css')
        base_prov = Gtk.CssProvider()
        if os.path.exists(base_css):
            base_prov.load_from_path(base_css)
        Gtk.StyleContext.add_provider_for_display(
            display, base_prov, Gtk.STYLE_PROVIDER_PRIORITY_USER)

        # notification-specific CSS
        notif_prov = Gtk.CssProvider()
        notif_prov.load_from_data(_NOTIFY_CSS)
        Gtk.StyleContext.add_provider_for_display(
            display, notif_prov, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)

        # dynamic CSS: heading font size (read once at startup; restart daemon to apply)
        ncfg      = notify_config.load()
        size_px   = ncfg.get('notify_heading_size_px', 14)
        dyn_prov  = Gtk.CssProvider()
        dyn_prov.load_from_string(f'.notif-summary {{ font-size: {size_px}px; }}')
        Gtk.StyleContext.add_provider_for_display(
            display, dyn_prov, Gtk.STYLE_PROVIDER_PRIORITY_USER + 2)

    # ── D-Bus callbacks ───────────────────────────────────────────────────────

    def _on_bus_acquired(self, conn: Gio.DBusConnection, _name: str) -> None:
        self._conn = conn
        node   = Gio.DBusNodeInfo.new_for_xml(_DBUS_XML)
        self._reg_id = conn.register_object(
            '/org/freedesktop/Notifications',
            node.interfaces[0],
            self._handle_method_call,
            None, None,
        )

    def _on_name_acquired(self, _conn, _name: str) -> None:
        pass

    def _on_name_lost(self, _conn, name: str) -> None:
        print(f'[notify] could not own {name} — another daemon may be running', flush=True)

    def _handle_method_call(
        self, conn, sender, obj_path, iface, method, params, invocation
    ) -> None:
        if method == 'GetCapabilities':
            caps = ['body', 'body-markup', 'actions', 'icon-static', 'persistence']
            invocation.return_value(GLib.Variant('(as)', (caps,)))

        elif method == 'GetServerInformation':
            invocation.return_value(
                GLib.Variant('(ssss)', ('vutureland-notify', 'vutureland', '1.0', '1.2')))

        elif method == 'Notify':
            (app_name, replaces_id, app_icon,
             summary, body, actions, hints, expire_timeout) = params.unpack()
            nid = self._notify(app_name, replaces_id, app_icon,
                               summary, body, list(actions), dict(hints), expire_timeout)
            invocation.return_value(GLib.Variant('(u)', (nid,)))

        elif method == 'CloseNotification':
            nid, = params.unpack()
            self._close(nid, REASON_CLOSED)
            invocation.return_value(None)

        else:
            invocation.return_dbus_error(
                'org.freedesktop.DBus.Error.UnknownMethod',
                f'Unknown method: {method}')

    # ── Notification logic ────────────────────────────────────────────────────

    def _notify(
        self,
        app_name:   str,
        replaces_id: int,
        app_icon:   str,
        summary:    str,
        body:       str,
        actions:    list[str],
        hints:      dict,
        timeout_ms: int,
    ) -> int:
        if replaces_id > 0 and replaces_id in self._active_ids():
            nid = replaces_id
        else:
            nid = self._next_id
            self._next_id += 1

        ncfg = notify_config.load()
        # Use the configured default timeout when the sender passes -1
        if timeout_ms < 0:
            timeout_ms = ncfg.get('notify_timeout_ms', 5000)

        _append_history(nid, replaces_id, app_name, app_icon, summary, body, hints)

        popup = NotifPopup(
            nid           = nid,
            app_name      = app_name,
            app_icon      = app_icon,
            summary       = summary,
            body          = body,
            actions       = actions,
            hints         = hints,
            timeout_ms    = timeout_ms,
            show_icons    = ncfg.get('notify_show_icons',    True),
            show_app_name = ncfg.get('notify_show_app_name', True),
            click_action  = ncfg.get('notify_click_action',  'dismiss'),
            dock_edge     = notify_config.dock_edge(ncfg),
            on_close      = self._close,
            on_action     = self._emit_action_invoked,
        )

        if replaces_id > 0 and self._window:
            self._window.replace_popup(replaces_id, popup)
        elif self._window:
            self._window.add_popup(popup)

        return nid

    def _close(self, nid: int, reason: int) -> None:
        if self._window:
            self._window.remove_popup(nid)
        self._emit_notification_closed(nid, reason)

    def _active_ids(self) -> set[int]:
        if self._window is None:
            return set()
        return set(self._window._entries.keys())

    # ── D-Bus signals ─────────────────────────────────────────────────────────

    def _emit_notification_closed(self, nid: int, reason: int) -> None:
        if self._conn is None:
            return
        try:
            self._conn.emit_signal(
                None,
                '/org/freedesktop/Notifications',
                'org.freedesktop.Notifications',
                'NotificationClosed',
                GLib.Variant('(uu)', (nid, reason)),
            )
        except Exception:
            pass

    def _emit_action_invoked(self, nid: int, action_key: str) -> None:
        if self._conn is None:
            return
        try:
            self._conn.emit_signal(
                None,
                '/org/freedesktop/Notifications',
                'org.freedesktop.Notifications',
                'ActionInvoked',
                GLib.Variant('(us)', (nid, action_key)),
            )
        except Exception:
            pass


# ── Entry point ───────────────────────────────────────────────────────────────

def _handle_flags() -> None:
    """Process --daemon / --end flags before GTK starts."""
    args = sys.argv[1:]

    if '-e' in args or '--end' in args:
        pid = _running_pid()
        if pid is not None:
            os.kill(pid, signal.SIGTERM)
        sys.exit(0)

    if '-d' in args or '--daemon' in args:
        sys.argv = [a for a in sys.argv if a not in ('-d', '--daemon')]
        if not _acquire_pid_lock():
            sys.exit(0)
    else:
        if not _acquire_pid_lock():
            print('[notify] daemon already running', flush=True)
            sys.exit(0)


if __name__ == '__main__':
    _handle_flags()
    NotifyDaemon().run()
