#!/usr/bin/env python3
"""KDE Connect bridge for the shell's phone module (stdlib + python-dbus).

Talks to the kdeconnectd daemon over D-Bus directly. Not through kdeconnect-cli: its output is
LOCALISED (it prints German on this machine), so parsing it would break the moment the locale
changes — and not through the KDE indicator app either, which is the whole point. Nothing here
opens a window; the shell renders everything itself.

Same contract as the other bridges (caldav-client.py, local-store.py): `list` prints the whole
state as one JSON line, actions are quiet and exit 0/1.

Commands:
  list                          {available, devices:[{id,name,type,reachable,paired,
                                                      battery{charge,charging,ok},
                                                      connectivity{type,strength,ok},
                                                      media{…}, notifs{…}, plugins}]}
  share <id> <path…>            send files (AirDrop-style; paths become file:// urls)
  share-text <id> <text>        send text / a link to the device's clipboard-share
  ring <id>                     make it ring (findmyphone)
  ping <id> [message]           a plain notification on the device
  media <id> <action>           PlayPause | Next | Previous | Stop on the phone's player
  media-player <id> <name>      switch which of the phone's players is being controlled
  media-volume <id> <0-100>     set the phone player's volume
  notif-dismiss <id> <nid>      dismiss one of the phone's notifications
  clipboard <id>                push this machine's clipboard to the device
  mount <id> | unmount <id>     mount the phone's filesystem over sftp
  storage <id>                  {mounted,path,total,used} — statvfs of the mount point
  pair <id> | unpair <id>
  pick                          run a file chooser, print the chosen paths (one per line)

D-Bus layout, all verified against a live daemon:
  /modules/kdeconnect                       org.kde.kdeconnect.daemon        devices()
  …/devices/<id>                            …device                          name,type,isReachable,isPaired
  …/devices/<id>/battery                    …device.battery                  charge, isCharging
  …/devices/<id>/connectivity_report        …device.connectivity_report      cellularNetworkType, …Strength
  …/devices/<id>/share                      …device.share                    shareUrl(s), shareUrls(as), shareText(s)
  …/devices/<id>/findmyphone                …device.findmyphone              ring()
  …/devices/<id>/ping                       …device.ping                     sendPing() / sendPing(s)
  …/devices/<id>/mprisremote                …device.mprisremote              player, title, artist, album,
                                                                             isPlaying, position, length,
                                                                             canSeek, volume,
                                                                             localAlbumArtUrl (a real file
                                                                             the daemon already cached, so
                                                                             the shell can just show it);
                                                                             sendAction(s), seek(x)
  …/devices/<id>/notifications              …device.notifications            activeNotifications()
  …/devices/<id>/notifications/<nid>        ….notifications.notification     appName, title, text, ticker,
                                                                             dismissable; dismiss()
  …/devices/<id>/clipboard                  …device.clipboard                sendClipboard()
  …/devices/<id>/sftp                       …device.sftp                     isMounted(), mountPoint(),
                                                                             mount(), unmount()

Every one of those is optional: the plugin can be unloaded, and the object path then does not exist
at all (checked — it raises UnknownObject rather than returning empty properties). So each block is
guarded and reports ok=false rather than failing the whole listing.
"""

import json
import os
import subprocess
import sys

SERVICE = "org.kde.kdeconnect"
ROOT = "/modules/kdeconnect"

try:
    import dbus
    # dbus-python LOGS an introspection failure through the logging module before it raises, so a
    # call against a device that just went away printed a stack-trace line into the shell's log
    # even though it is handled here. The exception is the report; the log line is noise.
    import logging
    logging.getLogger("dbus.proxies").setLevel(logging.CRITICAL)
except ImportError:                                  # pragma: no cover
    dbus = None


def _bus():
    return dbus.SessionBus() if dbus is not None else None


def _dev_path(dev_id):
    return "%s/devices/%s" % (ROOT, dev_id)


def _props(bus, path, iface):
    """All properties of one interface, or None when the plugin isn't loaded on that device."""
    try:
        obj = bus.get_object(SERVICE, path)
        return dict(dbus.Interface(obj, "org.freedesktop.DBus.Properties").GetAll(iface))
    except dbus.DBusException:
        return None


def _plain(v, default=None):
    """dbus types are int/str subclasses, but json.dump still chokes on some — normalise."""
    if v is None:
        return default
    if isinstance(v, dbus.Boolean):
        return bool(v)
    if isinstance(v, (dbus.Int16, dbus.Int32, dbus.Int64, dbus.UInt16, dbus.UInt32, dbus.UInt64, dbus.Byte)):
        return int(v)
    if isinstance(v, dbus.String):
        return str(v)
    return v


def _media(bus, path):
    """What the phone is playing, if anything. `player` empty = a plugin with no player attached,
    which is the normal state and not worth a card."""
    m = _props(bus, path + "/mprisremote", "org.kde.kdeconnect.device.mprisremote")
    if not m:
        return {"ok": False}
    player = _plain(m.get("player"), "") or ""
    title  = _plain(m.get("title"), "") or ""
    if player == "" and title == "":
        return {"ok": False}
    art = _plain(m.get("localAlbumArtUrl"), "") or ""
    # The daemon caches the cover as a real file; hand over only one that is actually there, so the
    # shell never has to reason about a broken image source.
    if art.startswith("file://") and not os.path.exists(art[7:]):
        art = ""
    players = []
    try:
        players = [str(x) for x in m.get("playerList") or []]
    except TypeError:
        pass
    return {
        "ok":       True,
        "player":   player,
        "players":  players,
        "title":    title,
        "artist":   _plain(m.get("artist"), "") or "",
        "album":    _plain(m.get("album"), "") or "",
        "playing":  bool(_plain(m.get("isPlaying"), False)),
        "canSeek":  bool(_plain(m.get("canSeek"), False)),
        "position": int(_plain(m.get("position"), 0) or 0),
        "length":   int(_plain(m.get("length"), 0) or 0),
        "volume":   int(_plain(m.get("volume"), -1) or -1),
        "art":      art,
    }


def _storage(bus, path):
    """Whether the phone's filesystem is mounted, and where. Both calls are D-Bus round trips to the
    daemon and cheap. The CAPACITY is deliberately NOT read here: statvfs on an sshfs whose phone
    walked out of range blocks, and this runs every 5 s while the panel is open — one dead mount
    would stall the whole listing. `storage` is a separate command for that reason."""
    try:
        i = dbus.Interface(bus.get_object(SERVICE, path + "/sftp"), "org.kde.kdeconnect.device.sftp")
        return {"ok": True, "mounted": bool(i.isMounted()), "path": str(i.mountPoint())}
    except dbus.DBusException:
        return {"ok": False, "mounted": False, "path": ""}


NOTIF_CAP = 8


def _notifs(bus, path):
    """The phone's own notifications. Capped: this is polled while the panel is open, and a phone
    with sixty of them would turn every refresh into sixty D-Bus round trips for rows nobody can
    see anyway. `total` still reports the honest number."""
    p = path + "/notifications"
    try:
        obj = bus.get_object(SERVICE, p)
        ids = [str(i) for i in dbus.Interface(
            obj, "org.kde.kdeconnect.device.notifications").activeNotifications()]
    except dbus.DBusException:
        return {"ok": False, "total": 0, "items": []}

    items = []
    for nid in ids[:NOTIF_CAP]:
        n = _props(bus, p + "/" + nid, "org.kde.kdeconnect.device.notifications.notification")
        if not n:
            continue
        title = _plain(n.get("title"), "") or ""
        text  = _plain(n.get("text"), "") or ""
        # Some senders fill only `ticker` ("Title: body") — better that than an empty row.
        if title == "" and text == "":
            title = _plain(n.get("ticker"), "") or ""
        items.append({
            "id":    nid,
            "app":   _plain(n.get("appName"), "") or "",
            "title": title,
            "text":  text,
            "icon":  _plain(n.get("iconPath"), "") or "",
            "dismissable": bool(_plain(n.get("dismissable"), False)),
        })
    return {"ok": True, "total": len(ids), "items": items}


def list_devices():
    bus = _bus()
    if bus is None:
        return {"available": False, "error": "python-dbus is not installed", "devices": []}
    try:
        daemon = dbus.Interface(bus.get_object(SERVICE, ROOT), "org.kde.kdeconnect.daemon")
        ids = [str(i) for i in daemon.devices()]
    except dbus.DBusException as e:
        # The daemon is D-Bus activatable, so this really means "not installed / can't start".
        return {"available": False, "error": str(e).split("\n")[0], "devices": []}

    out = []
    for dev_id in ids:
        path = _dev_path(dev_id)
        d = _props(bus, path, "org.kde.kdeconnect.device") or {}
        if not d:
            continue
        plugins = []
        try:
            plugins = [str(p) for p in dbus.Interface(
                bus.get_object(SERVICE, path), "org.kde.kdeconnect.device").loadedPlugins()]
        except dbus.DBusException:
            pass

        bat = _props(bus, path + "/battery", "org.kde.kdeconnect.device.battery")
        con = _props(bus, path + "/connectivity_report",
                     "org.kde.kdeconnect.device.connectivity_report")
        out.append({
            "id":        dev_id,
            "name":      _plain(d.get("name"), ""),
            "type":      _plain(d.get("type"), "phone"),
            "reachable": bool(_plain(d.get("isReachable"), False)),
            "paired":    bool(_plain(d.get("isPaired"), False)),
            "battery": {
                "ok":       bat is not None,
                "charge":   _plain(bat.get("charge"), -1) if bat else -1,
                "charging": bool(_plain(bat.get("isCharging"), False)) if bat else False,
            },
            "connectivity": {
                "ok":       con is not None,
                "type":     _plain(con.get("cellularNetworkType"), "") if con else "",
                "strength": _plain(con.get("cellularNetworkStrength"), -1) if con else -1,
            },
            "media":   _media(bus, path),
            "storage": _storage(bus, path),
            "notifs":  _notifs(bus, path),
            "plugins": plugins,
        })
    out.sort(key=lambda x: (not x["reachable"], x["name"].lower()))
    return {"available": True, "error": "", "devices": out}


def _call(dev_id, plugin, iface, method, *args):
    bus = _bus()
    if bus is None:
        sys.stderr.write("python-dbus is not installed\n")
        return False
    try:
        obj = bus.get_object(SERVICE, _dev_path(dev_id) + "/" + plugin)
        getattr(dbus.Interface(obj, iface), method)(*args)
        return True
    except dbus.DBusException as e:
        sys.stderr.write(str(e).split("\n")[0] + "\n")
        return False


def share(dev_id, paths):
    urls = []
    for p in paths:
        p = p.strip()
        if not p:
            continue
        if p.startswith(("file://", "http://", "https://")):
            urls.append(p)
        else:
            urls.append("file://" + os.path.abspath(os.path.expanduser(p)))
    if not urls:
        sys.stderr.write("nothing to share\n")
        return False
    return _call(dev_id, "share", "org.kde.kdeconnect.device.share",
                 "shareUrls", dbus.Array(urls, signature="s"))


def pick():
    """A file chooser without pulling in a KDE dialog — zenity is already here and is GTK."""
    try:
        r = subprocess.run(["zenity", "--file-selection", "--multiple", "--separator=\n",
                            "--title=Send to device"], capture_output=True, text=True)
    except OSError:
        sys.stderr.write("zenity is not installed\n")
        return 1
    if r.returncode != 0:
        return 1                                     # cancelled
    sys.stdout.write(r.stdout)
    return 0


def main():
    argv = sys.argv[1:]
    if not argv:
        sys.stderr.write(__doc__)
        return 2
    cmd, args = argv[0], argv[1:]

    if cmd == "list":
        json.dump(list_devices(), sys.stdout)
        sys.stdout.write("\n")
        return 0
    if cmd == "pick":
        return pick()
    if not args:
        sys.stderr.write("%s needs a device id\n" % cmd)
        return 2
    dev, rest = args[0], args[1:]

    if cmd == "share":
        return 0 if share(dev, rest) else 1
    if cmd == "share-text":
        return 0 if _call(dev, "share", "org.kde.kdeconnect.device.share",
                          "shareText", " ".join(rest)) else 1
    if cmd == "media" and rest:
        return 0 if _call(dev, "mprisremote", "org.kde.kdeconnect.device.mprisremote",
                          "sendAction", rest[0]) else 1
    if cmd in ("media-player", "media-volume") and rest:
        # `player` and `volume` are writable properties, not methods.
        bus = _bus()
        try:
            obj = bus.get_object(SERVICE, _dev_path(dev) + "/mprisremote")
            key = "player" if cmd == "media-player" else "volume"
            val = " ".join(rest) if key == "player" else dbus.Int32(int(rest[0]))
            dbus.Interface(obj, "org.freedesktop.DBus.Properties").Set(
                "org.kde.kdeconnect.device.mprisremote", key, val)
            return 0
        except (AttributeError, ValueError, dbus.DBusException) as e:
            sys.stderr.write(str(e).split("\n")[0] + "\n")
            return 1
    if cmd == "notif-dismiss" and rest:
        bus = _bus()
        try:
            obj = bus.get_object(SERVICE, _dev_path(dev) + "/notifications/" + rest[0])
            dbus.Interface(obj, "org.kde.kdeconnect.device.notifications.notification").dismiss()
            return 0
        except (AttributeError, dbus.DBusException) as e:
            sys.stderr.write(str(e).split("\n")[0] + "\n")
            return 1
    if cmd in ("mount", "unmount"):
        return 0 if _call(dev, "sftp", "org.kde.kdeconnect.device.sftp", cmd) else 1
    if cmd == "storage":
        bus = _bus()
        out = {"mounted": False, "path": "", "total": 0, "used": 0}
        try:
            i = dbus.Interface(bus.get_object(SERVICE, _dev_path(dev) + "/sftp"),
                               "org.kde.kdeconnect.device.sftp")
            out["mounted"] = bool(i.isMounted())
            out["path"] = str(i.mountPoint())
            if out["mounted"]:
                st = os.statvfs(out["path"])
                out["total"] = st.f_blocks * st.f_frsize
                out["used"] = (st.f_blocks - st.f_bfree) * st.f_frsize
        except (AttributeError, OSError, dbus.DBusException):
            pass
        json.dump(out, sys.stdout)
        sys.stdout.write("\n")
        return 0
    if cmd == "clipboard":
        return 0 if _call(dev, "clipboard", "org.kde.kdeconnect.device.clipboard",
                          "sendClipboard") else 1
    if cmd == "ring":
        return 0 if _call(dev, "findmyphone", "org.kde.kdeconnect.device.findmyphone", "ring") else 1
    if cmd == "ping":
        msg = " ".join(rest)
        return 0 if (_call(dev, "ping", "org.kde.kdeconnect.device.ping", "sendPing", msg) if msg
                     else _call(dev, "ping", "org.kde.kdeconnect.device.ping", "sendPing")) else 1
    if cmd in ("pair", "unpair"):
        bus = _bus()
        try:
            obj = bus.get_object(SERVICE, _dev_path(dev))
            iface = dbus.Interface(obj, "org.kde.kdeconnect.device")
            (iface.requestPair if cmd == "pair" else iface.unpair)()
            return 0
        except (AttributeError, dbus.DBusException) as e:
            sys.stderr.write(str(e).split("\n")[0] + "\n")
            return 1

    sys.stderr.write("unknown command: %s\n" % cmd)
    return 2


if __name__ == "__main__":
    sys.exit(main())
