// Live view of the active template + the template list. settings.json stays the effective config
// (VtlConfig/Colors read it as before); templates are just named, *applyable* snapshots of it — the
// shipped defaults (mirobo …) plus any preset the user explicitly saves. There is deliberately NO
// auto-sync: changing a setting only writes settings.json (in ~/.config, so it survives updates) and
// never forks a new template. Applying a template full-replaces settings.json from its snapshot
// (device-bound keys preserved). All file I/O lives in assets/scripts/velumeron-config.py.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string _dir: Quickshell.env("VELUMERON_DIR") || ""
    readonly property string _cli:          _dir + "/assets/scripts/velumeron-config.py"

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
    // "Save as preset" flow: snapshot the current settings.json into a new named user template. It does
    // NOT become active — settings.json stays the live config; the preset is just there to apply later.
    function createAndBuild(name)        { _mut(["new", name || ""]) }
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

    // ── Startup: one-time migration (adopt current settings / point at Mirobo), then load the list ──
    property bool _booted: false
    function boot() {
        if (_booted) return
        _booted = true
        _mut(["init"])   // init is idempotent; _mutProc's onRunningChanged then refreshes the list
    }
    Component.onCompleted: boot()
}
