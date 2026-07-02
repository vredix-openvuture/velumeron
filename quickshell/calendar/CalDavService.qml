pragma Singleton
import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// CalDAV state shared by the calendar menu (clock flyout) and the calendar settings page.
// All network work lives in assets/scripts/caldav-client.py; every command it runs prints
// the full JSON cache on stdout, so load / sync / mutations share one parse path. Commands
// queue through a single Process (a fast double-click on two todos must not kill the first
// PUT mid-flight). Mutations patch the local model optimistically; the cache that comes
// back confirms (or corrects) it.
Singleton {
    id: root

    property var    data:      ({ syncedAt: 0, accounts: [], calendars: [], events: [], todos: [] })
    property bool   syncing:   false
    property string lastError: ""

    readonly property string script: Quickshell.env("VELUMERON_DIR") + "/assets/scripts/caldav-client.py"

    readonly property var accounts:  data.accounts  ?? []
    readonly property var calendars: data.calendars ?? []
    readonly property bool hasAccounts: accounts.length > 0

    // Visible = not hidden in Settings → Calendar (caldav_hidden.<calId> = true).
    readonly property var events: (data.events ?? []).filter(e => !VtlConfig.caldavCalHidden(e.cal))
    readonly property var todos:  (data.todos  ?? []).filter(t => !VtlConfig.caldavCalHidden(t.cal))

    // Writable targets for the quick-add rows.
    readonly property var eventCalendars: calendars.filter(c => c.vevent && c.writable)
    readonly property var todoCalendars:  calendars.filter(c => c.vtodo  && c.writable)

    // Open tasks that are overdue or due today — the clock module shows a dot when > 0.
    readonly property int dueCount: {
        var end = new Date(); end.setHours(23, 59, 59, 999)
        var n = 0
        for (var i = 0; i < todos.length; i++)
            if (!todos[i].completed && todos[i].dueMs > 0 && todos[i].dueMs <= end.getTime()) n++
        return n
    }

    function calById(id) {
        for (var i = 0; i < calendars.length; i++) if (calendars[i].id === id) return calendars[i]
        return null
    }
    // Calendar colour: the server-provided one, else a stable palette pick by index.
    function colorFor(calId) {
        var c = calById(calId)
        if (c && c.color) return c.color
        var pal = [Colors.bgActive, Colors.boActive, Colors.bgHover, Colors.boNormal, Colors.bgSecondary]
        var idx = 0
        for (var i = 0; i < calendars.length; i++) if (calendars[i].id === calId) { idx = i; break }
        return pal[idx % pal.length]
    }

    // ── Command queue (one Process; every command prints the fresh cache) ────────
    property var _queue: []
    function _run(args) { _queue.push(args); _pump() }
    function _pump() {
        if (proc.running || root._queue.length === 0) return
        proc.command = ["python3", root.script].concat(root._queue.shift())
        proc.running = true
    }
    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                var t = ("" + text).trim()
                if (t !== "") {
                    try {
                        var d = JSON.parse(t)
                        root.data = d
                        root.lastError = d.lastError ?? ""
                    } catch (e) { /* keep the previous model on a garbled read */ }
                }
                root.syncing = root._queue.some(a => a[0] === "sync")
                Qt.callLater(root._pump)
            }
        }
        onExited: Qt.callLater(root._pump)
    }

    function sync() {
        if (root._queue.some(a => a[0] === "sync")) return   // one pending refresh is enough
        root.syncing = true
        _run(["sync"])
    }

    // ── Mutations (optimistic where it matters) ─────────────────────────────────
    function addTodo(calId, summary, dueYmd) {
        var args = ["add-todo", calId, summary]
        if (dueYmd) args.push(dueYmd)
        _run(args)
    }

    function toggleTodo(todo) {
        var d = Object.assign({}, root.data)
        d.todos = (d.todos ?? []).map(t =>
            (t.href === todo.href && t.cal === todo.cal)
                ? Object.assign({}, t, { completed: !t.completed,
                                         doneMs: !t.completed ? Date.now() : 0 })
                : t)
        root.data = d
        _run(["toggle-todo", todo.cal, todo.href, todo.completed ? "0" : "1"])
    }

    function deleteItem(calId, href) {
        var d = Object.assign({}, root.data)
        d.todos  = (d.todos  ?? []).filter(t => !(t.href === href && t.cal === calId))
        d.events = (d.events ?? []).filter(e => !(e.href === href && e.cal === calId))
        root.data = d
        _run(["delete-item", calId, href])
    }

    function addEvent(calId, summary, ymd, hm, durationMin) {
        _run(["add-event", calId, summary, ymd, hm ?? "", "" + (durationMin ?? 60)])
    }

    // Account management (settings page). Credentials go via the environment, not argv.
    function addAccount(name, url, user, pass) {
        accountProc.environment = ({ CD_NAME: name, CD_URL: url, CD_USER: user, CD_PASS: pass })
        accountProc.running = false
        accountProc.running = true
    }
    property bool   accountBusy:  false
    property string accountError: ""
    Process {
        id: accountProc
        command: ["python3", root.script, "add-account"]
        onStarted: { root.accountBusy = true; root.accountError = "" }
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.data = JSON.parse(("" + text).trim()) } catch (e) {}
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                var t = ("" + text).trim()
                if (t !== "") root.accountError = t.split("\n").pop()
            }
        }
        onExited: (code) => {
            root.accountBusy = false
            if (code === 0) root.accountError = ""
            else if (root.accountError === "") root.accountError = "could not connect"
        }
    }
    function removeAccount(name) { _run(["remove-account", name]) }

    // ── Startup: instant cache, then a real sync; refresh on the configured cadence ──
    Component.onCompleted: { _run(["load"]); sync() }
    Timer {
        interval: Math.max(2, VtlConfig.caldavSyncMinutes) * 60000
        repeat:   true
        running:  root.hasAccounts
        onTriggered: root.sync()
    }
}
