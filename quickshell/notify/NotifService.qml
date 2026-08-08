pragma Singleton
import ".."
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
    property var  popups: []                       // [Notification] currently toasting (incl. retracting)
    property var  _deadlines: ({})                 // notification.id → epoch-ms expiry (0 = never)
    // A toast isn't yanked the instant it's dropped — it plays a retract animation first. `_leaving`
    // keeps it in `popups` meanwhile (id → epoch-ms the retract began); `_dismissOnPurge` remembers
    // whether to fully dismiss it (vs. just drop the toast) once gone; `_seen` marks toasts that have
    // already entered, so a delegate recreated by a popups-array change doesn't replay the entrance.
    property var  _leaving:        ({})            // notification.id → epoch-ms retract start
    property var  _dismissOnPurge: ({})            // notification.id → true → dismiss on purge
    property var  _seen:           ({})            // notification.id → true (has entered)
    property var  pinned: ({})                     // notification.id → true; pinned entries sort to the
                                                   // top of the centre and survive "clear all"
    readonly property var model: serverLoader.item ? serverLoader.item.trackedNotifications : null   // history (null while the notifications component is off)

    function isPinned(n) { return !!(n && root.pinned[n.id]) }
    function togglePin(n) {
        if (!n) return
        var m = Object.assign({}, root.pinned)
        if (m[n.id]) delete m[n.id]; else m[n.id] = true
        root.pinned = m
    }

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

    // ── "Take me to whatever wants my attention" ────────────────────────────────────────────────
    // Clicking a notification should land you in the app that sent it. Two mechanisms do that and
    // they complement each other: the freedesktop "default" action is how an app says WHICH mail or
    // chat to open — but plenty of notifications carry no actions at all, and even those that do
    // don't necessarily raise their window. So invoke the action when there is one, AND focus the
    // sender's window when one can be found. Shared by the toasts and the centre; the two used to
    // only invoke the action, which is why most notifications did nothing at all when clicked.
    function defaultActionOf(n) {
        if (!n) return null
        var acts = (n.actions && n.actions.values) ? n.actions.values : (n.actions || [])
        for (var i = 0; i < acts.length; i++) if (acts[i].identifier === "default") return acts[i]
        return null
    }

    // Every string that could name the sender's window class. A notification names its app the way
    // a human would ("Telegram Desktop"); Hyprland knows windows by class ("org.telegram.desktop"),
    // so the desktop entry is the bridge — its startupClass IS that class.
    function _appKeys(n) {
        var keys = []
        function add(s) {
            var v = ("" + (s ?? "")).trim().toLowerCase()
            if (v !== "" && keys.indexOf(v) < 0) keys.push(v)
        }
        var e = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null
        if (!e && n.appName) e = DesktopEntries.heuristicLookup(n.appName)
        if (e) { add(e.startupClass); add(e.id) }
        add(n.desktopEntry)
        add(n.appName)
        var an = ("" + (n.appName ?? "")).trim().toLowerCase()
        if (an.indexOf(" ") > 0) { add(an.split(" ")[0]); add(an.replace(/\s+/g, "")) }
        return keys
    }

    // The sender's window, or null. An exact class match wins over a partial one (partials are
    // needed for the "firefox" / "firefox-esr" kind of near-miss, and capped at 4 characters so a
    // short name can't match half the desktop); among equals, the most recently focused window.
    function windowFor(n) {
        if (!n) return null
        var keys = root._appKeys(n)
        if (keys.length === 0) return null
        var ws = Hyprwindows.windows
        var best = null, bestScore = 0
        for (var i = 0; i < ws.length; i++) {
            var cls = ("" + (ws[i].cls ?? "")).toLowerCase()
            if (cls === "") continue
            var score = 0
            for (var k = 0; k < keys.length; k++) {
                var key = keys[k]
                if (cls === key) { score = 2; break }
                if (key.length >= 4 && (cls.indexOf(key) >= 0 || key.indexOf(cls) >= 0)) score = 1
            }
            if (score === 0) continue
            if (score > bestScore || (score === bestScore && best
                                      && (ws[i].fhi ?? 999) < (best.fhi ?? 999))) {
                best = ws[i]; bestScore = score
            }
        }
        return best
    }

    // Focus lands a beat late on purpose: the notification centre holds an OnDemand keyboard grab,
    // and Hyprland restores focus when that grab drops — a dispatch sent before the panel is gone
    // is simply overridden by the restore (the same trap WindowSwitcher documents).
    Timer {
        id: focusTimer
        interval: 130; repeat: false
        property string addr: ""
        onTriggered: if (focusTimer.addr !== "") Compositor.focusWindowAddress(focusTimer.addr)
    }
    function focusWindowOf(n) {
        var w = root.windowFor(n)
        if (!w || !w.address) return false
        focusTimer.addr = "" + w.address
        focusTimer.restart()
        return true
    }

    // Returns true when the click led somewhere — the callers use that to decide between dropping
    // just the toast and dismissing the notification outright.
    function activate(n) {
        if (!n) return false
        var acted = false
        var a = root.defaultActionOf(n)
        if (a) { a.invoke(); acted = true }
        if (root.focusWindowOf(n)) acted = true
        return acted
    }

    // The D-Bus server is gated on the `notifications` component: with it OFF, velumeron never
    // registers org.freedesktop.Notifications, so mako/dunst/swaync can own it instead. The Loader
    // destroys the server (releasing the name) the instant the feature is switched off, and
    // re-creates it when switched back on.
    Loader {
        id: serverLoader
        active: VtlConfig.componentEnabled("notifications")
        sourceComponent: Component {
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
        }
    }

    // Auto-dismiss is driven here (not in the toast delegate, which gets recreated whenever the
    // popups array changes — that reset the per-toast timers, so popups could get stuck on a
    // steady stream of notifications). A single sweep drops popups past their deadline.
    Timer {
        interval: 250; repeat: true; running: root.popups.length > 0
        onTriggered: {
            var now = Date.now()
            // Start the retract on anything past its deadline (it stays in `popups` until it has
            // finished animating out and its delegate calls purge()).
            for (var i = 0; i < root.popups.length; i++) {
                var n  = root.popups[i]
                var dl = root._deadlines[n.id]
                if (dl && dl > 0 && now >= dl) root.startLeave(n, false)
            }
            // Fallback: a toast stuck "leaving" too long (its delegate was recreated / never signalled)
            // is force-purged so it can't sit invisibly holding a slot.
            for (var id in root._leaving) {
                if (now - root._leaving[id] <= 800) continue
                var victim = null
                for (var k = 0; k < root.popups.length; k++)
                    if (("" + root.popups[k].id) === ("" + id)) { victim = root.popups[k]; break }
                if (victim) root.purge(victim)
                else { var m = Object.assign({}, root._leaving); delete m[id]; root._leaving = m }
            }
        }
    }

    function isLeaving(n) { return !!(n && root._leaving[n.id] !== undefined) }
    function wasSeen(n)   { return !!(n && root._seen[n.id]) }
    function markSeen(n)  {
        if (!n || root._seen[n.id]) return
        var m = Object.assign({}, root._seen); m[n.id] = true; root._seen = m
    }

    // Begin the retract (exit) animation: keep n in `popups` so its toast can play the reverse morph,
    // and remember whether to fully dismiss it (vs. just drop the toast) once it's gone.
    function startLeave(n, doDismiss) {
        if (!n) return
        if (doDismiss && !root._dismissOnPurge[n.id]) {
            var d = Object.assign({}, root._dismissOnPurge); d[n.id] = true; root._dismissOnPurge = d
        }
        if (root._leaving[n.id] !== undefined) return          // already retracting
        var m = Object.assign({}, root._leaving); m[n.id] = Date.now(); root._leaving = m
    }

    // Actually remove n once its toast has finished retracting (called by the delegate, or the
    // fallback sweep above). Clears its bookkeeping and dismisses it if that was requested.
    function purge(n) {
        if (!n) return
        var doDismiss = !!root._dismissOnPurge[n.id]
        if (root.popups.indexOf(n) >= 0)
            root.popups = root.popups.filter(function (x) { return x !== n })
        if (root._leaving[n.id]        !== undefined) { var a = Object.assign({}, root._leaving);        delete a[n.id]; root._leaving = a }
        if (root._dismissOnPurge[n.id] !== undefined) { var b = Object.assign({}, root._dismissOnPurge); delete b[n.id]; root._dismissOnPurge = b }
        if (root._seen[n.id]           !== undefined) { var c = Object.assign({}, root._seen);           delete c[n.id]; root._seen = c }
        if (doDismiss && n.dismiss) n.dismiss()
    }

    // Drop just the toast (notification stays in the centre) — retract, then purge.
    function dropPopup(n) { root.startLeave(n, false) }

    // Dismiss the notification entirely — retract the toast, and dismiss() it once it's gone (deferred
    // so n stays valid while its delegate is still animating out).
    function dismiss(n) { root.startLeave(n, true) }

    function clearAll() {
        // Pinned entries are kept — "clear all" only sweeps the un-pinned history + toasts. Visible
        // toasts retract (dismissed on purge); the rest are dismissed straight away.
        var vs = serverLoader.item ? serverLoader.item.trackedNotifications.values : []
        for (var i = vs.length - 1; i >= 0; i--) {
            var n = vs[i]
            if (root.isPinned(n)) continue
            if (root.popups.indexOf(n) >= 0) root.startLeave(n, true)
            else if (n.dismiss) n.dismiss()
        }
    }

    function toggleDnd() { root.dnd = !root.dnd }
}
