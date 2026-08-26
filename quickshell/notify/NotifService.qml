pragma Singleton
import ".."
import QtQuick
import Quickshell
import Quickshell.Io
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

    // ── `popups` is a Repeater model, so writing it REBUILDS the whole toast stack ───────────────
    // Every assignment makes QQuickRepeater destroy and re-incubate every delegate. Doing that from
    // inside a callback Qt is still unwinding crashes the process in QtQmlModels — and this file had
    // two of them: the D-Bus dispatch that delivers a notification (`onNotification`) and a
    // SpringAnimation tick reporting a card finished retracting (`purge` from `onRevealChanged`).
    // Five SIGSEGVs in four days, all with the same QQuickRepeater::regenerate frame. quickshell is
    // ONE process, so that is also what "the bar just disappeared" was.
    //
    // Nothing writes `popups` directly any more. Writes queue and land on the next event-loop turn,
    // which is the only moment a tree rebuild is safe. Reads go through livePopups(), so a second
    // change queued in the same turn still sees the first one instead of the stale array.
    property var _queued: null
    function livePopups() { return root._queued !== null ? root._queued : root.popups }
    function _setPopups(a) {
        root._queued = a
        Qt.callLater(root._flushPopups)
    }
    function _flushPopups() {
        if (root._queued === null) return
        var a = root._queued
        root._queued = null
        root.popups = a
    }

    // A notification the sender withdrew (CloseNotification) or the server expired is DESTROYED,
    // and a toast still holding that object renders as a card with no app, no summary and no body —
    // the "dead notification". It never leaves either: every timer here matches on `n.id`, and a
    // destroyed object has no id, so neither the deadline sweep nor `_leaving` can ever find it.
    // The id is captured while the object is still alive, because `closed` fires on its way out.
    function _forget(n, id) {
        var live = root.livePopups()
        var a = live.filter(function (x) { return x !== n })
        if (a.length !== live.length) root._setPopups(a)
        if (root._deadlines[id] !== undefined) delete root._deadlines[id]
        if (root._leaving[id] !== undefined)        { var m = Object.assign({}, root._leaving);        delete m[id]; root._leaving = m }
        if (root._dismissOnPurge[id] !== undefined) { var d = Object.assign({}, root._dismissOnPurge); delete d[id]; root._dismissOnPurge = d }
        if (root._seen[id] !== undefined)           { var s = Object.assign({}, root._seen);           delete s[id]; root._seen = s }
    }

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

    // ── "The notification is ABOUT a file" ──────────────────────────────────────────────────────
    // A screenshot toast has no window to focus and no app to raise: the thing you want is the PNG,
    // in whatever viewer this system opens PNGs with. Two sources say which file, in order of how
    // deliberately the sender meant it — the explicit x-velumeron-open hint (our own screenshot.sh
    // sets it), then the picture the notification carries, because a screenshot tool passes the
    // shot itself as the notification image/icon.
    function _fileTarget(s) {
        var p = "" + (s ?? "")
        if (p.indexOf("file://") === 0) p = decodeURIComponent(p.substring(7))
        if (p.indexOf("/") !== 0) return ""                  // an icon NAME, or an image:// uri
        // A themed icon is a real file too, and opening telegram.svg in an image viewer is not what
        // clicking a chat message meant. Only documents outside the icon dirs qualify.
        if (p.indexOf("/icons/") >= 0 || p.indexOf("/pixmaps/") >= 0) return ""
        if (/\.(svg|svgz|xpm|ico)$/i.test(p)) return ""
        return p
    }
    function openTargetOf(n) {
        if (!n) return ""
        var h = n.hints
        var v = h ? h["x-velumeron-open"] : null
        if (v) return root._fileTarget(v)
        return root._fileTarget(n.image) || root._fileTarget(n.appIcon)
    }
    // setsid -f, so the viewer outlives this process and never becomes our child.
    Process { id: openProc }
    function openTarget(n) {
        var p = root.openTargetOf(n)
        if (p === "") return false
        openProc.running = false
        openProc.command = ["setsid", "-f", "xdg-open", p]
        openProc.running = true
        return true
    }

    // Returns true when the click led somewhere — the callers use that to decide between dropping
    // just the toast and dismissing the notification outright.
    function activate(n) {
        if (!n) return false
        var acted = false
        // An explicit open target beats the freedesktop action, and is NOT combined with it: both
        // would open the same file twice. It also outlives the action — `notify-send -A` only
        // answers while that process is alive, and a notification you come back to in the centre
        // an hour later has long lost it. That is why clicking an old screenshot did nothing.
        var h = n.hints
        if (h && h["x-velumeron-open"] && root.openTarget(n)) return true
        var a = root.defaultActionOf(n)
        if (a) { a.invoke(); acted = true }
        if (root.focusWindowOf(n)) acted = true
        // Nothing claimed the click: the file the notification is about is the last thing left to
        // go to (a screenshot from any other tool lands here).
        if (!acted) acted = root.openTarget(n)
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

                // True when the sender asked for no sound. Hints arrive under different shapes
                // depending on the client, so accept the plain key as well as the string form.
                function _silentHint(n) {
                    var h = n.hints
                    if (!h) return false
                    var v = h["x-velumeron-silent"]
                    return v === true || v === 1 || v === "1" || v === "true"
                }

                onNotification: function (n) {
                    n.tracked = true
                    root.unread++
                    // Withdrawn / expired notifications have to leave the toast list themselves —
                    // see NotifService._forget. Connected before anything else so a notification
                    // closed in the same breath as it arrived is still caught.
                    var nid = n.id
                    n.closed.connect(function () { root._forget(n, nid) })
                    if (!root.dnd) {
                        var critical = (n.urgency === NotificationUrgency.Critical)
                        // Split by urgency deliberately: the everyday one is off by default and the
                        // critical one on, so the sound still means something when you do hear it.
                        // Inside the !dnd branch — do-not-disturb silences the toast, and a shell
                        // that hides the popup but still beeps has not understood the request.
                        //
                        // A notification that merely REPORTS an action the shell already made a
                        // sound for stays silent. The screenshot is the case that exposed this: the
                        // shutter fires when the capture succeeds, and the "saved" toast that
                        // follows it fired the notification sound a moment later — one action, two
                        // different sounds. Senders opt out with the x-velumeron-silent hint;
                        // notify-send passes it through unchanged.
                        if (!_silentHint(n))
                            SoundService.play(critical ? "notification-critical" : "notification")
                        var to = (n.expireTimeout > 0 ? n.expireTimeout : 5000)
                        root._deadlines[n.id] = critical ? 0 : (Date.now() + to)
                        var a = root.livePopups().filter(function (x) { return x !== n })
                        a.unshift(n)
                        root._setPopups(a)      // deferred — we are inside the D-Bus dispatch
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
            var live = root.livePopups()
            // Belt and braces for the dead card: anything whose object is gone reads back with no
            // id, which means neither the deadline pass below nor `_leaving` can ever match it —
            // it would sit there blank forever. `closed` normally catches these (see _forget); this
            // catches one that slipped through, e.g. a notification already on its way out when the
            // server was created.
            var alive = live.filter(function (n) { return n && n.id !== undefined })
            if (alive.length !== live.length) { root._setPopups(alive); live = alive }
            // Start the retract on anything past its deadline (it stays in `popups` until it has
            // finished animating out and its delegate calls purge()).
            for (var i = 0; i < live.length; i++) {
                var n  = live[i]
                var dl = root._deadlines[n.id]
                if (dl && dl > 0 && now >= dl) root.startLeave(n, false)
            }
            // Fallback: a toast stuck "leaving" too long (its delegate was recreated / never signalled)
            // is force-purged so it can't sit invisibly holding a slot.
            for (var id in root._leaving) {
                if (now - root._leaving[id] <= 800) continue
                var victim = null
                for (var k = 0; k < live.length; k++)
                    if (("" + live[k].id) === ("" + id)) { victim = live[k]; break }
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
        var live = root.livePopups()
        if (live.indexOf(n) >= 0)
            root._setPopups(live.filter(function (x) { return x !== n }))
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
        var live = root.livePopups()
        for (var i = vs.length - 1; i >= 0; i--) {
            var n = vs[i]
            if (root.isPinned(n)) continue
            if (live.indexOf(n) >= 0) root.startLeave(n, true)
            else if (n.dismiss) n.dismiss()
        }
    }

    function toggleDnd() { root.dnd = !root.dnd }
}
