pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// The org.freedesktop.Notifications server + shared state. Owns the D-Bus name (so the old
// Python daemon / swaync must not run). `server.trackedNotifications` is the history; `popups`
// is the subset currently shown as toasts.
Singleton {
    id: root

    property bool dnd:    false
    property int  unread: 0                         // since the centre was last opened (bell indicator)
    property var  popups: []                       // [Notification] currently toasting
    property var  _deadlines: ({})                 // notification.id → epoch-ms expiry (0 = never)
    readonly property var model: server.trackedNotifications   // ObjectModel — history

    // Best icon source for a notification, so a toast/entry can ALWAYS show the sending app's icon:
    // its own image hint (album art …) → its app-icon hint → the sending app's desktop-entry icon
    // (resolved from the desktop-entry hint, else heuristically from the app name). "" only when
    // nothing at all resolves — callers then fall back to a generic glyph.
    function iconFor(n) {
        if (!n) return ""
        if (n.image) return n.image
        if (n.appIcon)
            return (("" + n.appIcon).indexOf("/") === 0 || ("" + n.appIcon).indexOf("file:") === 0)
                 ? n.appIcon : Quickshell.iconPath(n.appIcon, "application-x-executable")
        var e = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null
        if (!e && n.appName) e = DesktopEntries.heuristicLookup(n.appName)
        return (e && e.icon) ? Quickshell.iconPath(e.icon, "application-x-executable") : ""
    }

    NotificationServer {
        id: server
        keepOnReload:        false
        imageSupported:      true
        actionsSupported:    true
        bodySupported:       true
        bodyMarkupSupported: true
        persistenceSupported: true

        onNotification: function (n) {
            n.tracked = true
            root.unread++
            if (!root.dnd) {
                var critical = (n.urgency === NotificationUrgency.Critical)
                var to = (n.expireTimeout > 0 ? n.expireTimeout : 5000)
                root._deadlines[n.id] = critical ? 0 : (Date.now() + to)
                var a = root.popups.filter(function (x) { return x !== n })
                a.unshift(n)
                root.popups = a
            }
        }
    }

    // Auto-dismiss is driven here (not in the toast delegate, which gets recreated whenever the
    // popups array changes — that reset the per-toast timers, so popups could get stuck on a
    // steady stream of notifications). A single sweep drops popups past their deadline.
    Timer {
        interval: 250; repeat: true; running: root.popups.length > 0
        onTriggered: {
            var now = Date.now(), keep = [], changed = false
            for (var i = 0; i < root.popups.length; i++) {
                var n  = root.popups[i]
                var dl = root._deadlines[n.id]
                if (dl && dl > 0 && now >= dl) { changed = true; continue }
                keep.push(n)
            }
            if (changed) root.popups = keep
        }
    }

    function dropPopup(n) { root.popups = root.popups.filter(function (x) { return x !== n }) }

    function dismiss(n) {
        root.dropPopup(n)
        if (n) n.dismiss()
    }

    function clearAll() {
        var vs = server.trackedNotifications.values
        for (var i = vs.length - 1; i >= 0; i--) vs[i].dismiss()
        root.popups = []
    }

    function toggleDnd() { root.dnd = !root.dnd }
}
