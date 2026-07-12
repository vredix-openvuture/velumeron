// Live view of the active template + the template list, and the copy-on-write watcher that keeps the
// shipped presets pristine. settings.json stays the effective config (VtlConfig/Colors read it as
// before); this singleton just reconciles it with the active template via assets/scripts/
// velumeron-config.py. A FileView on settings.json fires a debounced `sync` after ANY write (whichever
// settings page did it), so "the user changed something -> it becomes their own template" is guaranteed
// without touching a single existing writer. All file I/O + fork logic lives in the Python CLI.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string _dir: Quickshell.env("VELUMERON_DIR") || ""
    readonly property string _userDir: {
        var u = Quickshell.env("VELUMERON_USER_DIR")
        if (u) return u
        var xdg = Quickshell.env("XDG_CONFIG_HOME")
        if (xdg) return xdg + "/velumeron"
        return Quickshell.env("HOME") + "/.config/velumeron"
    }
    readonly property string _cli:          _dir + "/assets/scripts/velumeron-config.py"
    readonly property string _settingsPath: _userDir + "/gui/settings.json"

    // ── Reactive state (parsed from the CLI's `list`) ────────────────────────────────────────────
    property var    templates:       []     // [{ id, name, author, builtin, source, active }]
    property string activeId:        ""
    property string activeSource:    ""
    property string activeName:      ""
    property bool   activeIsBuiltin: false

    // ── Public API (used by Settings → Style → TEMPLATE) ─────────────────────────────────────────
    function activate(source, id)        { _mut(["activate", source, id]) }
    function duplicate(source, id, name) { _mut((name && name.length) ? ["duplicate", source, id, name]
                                                                      : ["duplicate", source, id]) }
    function create(name)                { _mut(["new", name || ""]) }
    // Theme-builder flow: snapshot the current settings as a new user template AND activate it,
    // so every builder step edits the fresh template live (copy-on-write persists into it).
    function createAndBuild(name)        { _mut(["new", name || "", "activate"]) }
    function rename(id, name)            { if (name && name.length) _mut(["rename", id, name]) }
    function remove(id)                  { _mut(["delete", id]) }
    function refresh() {
        _listProc.command = ["python3", root._cli, "list"]
        _listProc.running = false; _listProc.running = true
    }

    function _mut(args) {
        _mutProc.command = ["python3", root._cli].concat(args)
        _mutProc.running = false; _mutProc.running = true
    }

    // ── Processes ────────────────────────────────────────────────────────────────────────────────
    // Mutations (activate/duplicate/rename/delete/new/init) — refresh the list when they finish.
    readonly property Process _mutProc: Process {
        onRunningChanged: if (!running) root.refresh()
    }
    // The debounced copy-on-write sync — refresh afterwards so a fork's new active shows up.
    readonly property Process _syncProc: Process {
        onRunningChanged: if (!running) root.refresh()
    }
    // `list` output is a single JSON line; accumulate then parse on stop.
    property string _listBuf: ""
    readonly property Process _listProc: Process {
        stdout: SplitParser { onRead: line => { root._listBuf += line } }
        onRunningChanged: {
            if (running) { root._listBuf = ""; return }
            root._applyList(root._listBuf)
        }
    }

    function _applyList(txt) {
        var d
        try { d = JSON.parse(("" + txt).trim()) } catch (e) { return }
        var act = d.active || {}
        var out = []
        function tag(arr) {
            for (var i = 0; i < (arr ? arr.length : 0); i++) {
                var t = arr[i]
                t.active = (t.id === act.id && t.source === act.source)
                out.push(t)
            }
        }
        tag(d.builtin); tag(d.user)
        root.templates       = out
        root.activeId        = act.id || ""
        root.activeSource    = act.source || ""
        var an = "", ab = false
        for (var j = 0; j < out.length; j++) if (out[j].active) { an = out[j].name; ab = !!out[j].builtin }
        root.activeName      = an
        root.activeIsBuiltin = ab
    }

    // ── Copy-on-write watcher: any settings.json write → debounced `sync` ─────────────────────────
    readonly property FileView _settingsWatch: FileView {
        path:         root._settingsPath
        watchChanges: true
        onFileChanged: { reload(); root._debounce.restart() }
    }
    readonly property Timer _debounce: Timer {
        interval: 600; repeat: false
        onTriggered: {
            root._syncProc.command = ["python3", root._cli, "sync"]
            root._syncProc.running = false; root._syncProc.running = true
        }
    }

    // ── Startup: one-time migration (adopt current settings / point at Mirobo), then load the list ──
    property bool _booted: false
    function boot() {
        if (_booted) return
        _booted = true
        _mut(["init"])   // init is idempotent; _mutProc's onRunningChanged then refreshes the list
    }
    Component.onCompleted: boot()
}
