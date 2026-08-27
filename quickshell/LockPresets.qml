pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Reactive wrapper around assets/scripts/lockscreen-config.py — the lockscreen preset registry
// (mirror of Templates.qml, scoped to the lock). Holds no file I/O itself: every mutation shells
// out to the CLI, which merges a preset's lock_* keys into gui/settings.json (VtlConfig then
// recolours the lock live) and maintains active-lockscreen.json. See VtlConfig.lock* / LockContent.
QtObject {
    id: root
    readonly property string _cli: (Quickshell.env("VELUMERON_DIR") || "") + "/assets/scripts/lockscreen-config.py"

    property var    presets:      []          // [{ id, name, author, builtin, source, active, settings }]
    property string activeId:     "console"
    property string activeSource: "builtin"

    function presetById(id, source) {
        for (var i = 0; i < root.presets.length; i++)
            if (root.presets[i].id === id && (!source || root.presets[i].source === source)) return root.presets[i]
        return null
    }

    // ── list / refresh ──────────────────────────────────────────────────────────
    property Process _listProc: Process {
        command: ["python3", root._cli, "list"]
        stdout: StdioCollector { onStreamFinished: root._apply(this.text) }
    }
    function refresh() { root._listProc.running = false; root._listProc.running = true }
    function _apply(t) {
        try {
            var d = JSON.parse(("" + t).trim())
            root.presets      = d.presets || []
            root.activeId     = d.activeId || "console"
            root.activeSource = d.activeSource || "builtin"
        } catch (e) { /* keep last good */ }
    }

    // ── mutations (each re-lists on completion) ───────────────────────────────────
    property Process _mutProc: Process { onExited: root.refresh() }
    function _mut(args) {
        root._mutProc.command = ["python3", root._cli].concat(args)
        root._mutProc.running = false
        root._mutProc.running = true
    }

    function activate(source, id)      { root._mut(["activate", source, id]) }
    function saveAs(name, settings)    { root._mut(["save", name, JSON.stringify(settings)]) }
    function duplicate(source, id, name) { root._mut(["duplicate", source, id, name]) }
    function rename(id, name)          { root._mut(["rename", id, name]) }
    function remove(id)                { root._mut(["delete", id]) }

    property bool _booted: false
    function boot() { if (root._booted) return; root._booted = true; root._mut(["init"]) }  // _mut refreshes after
    Component.onCompleted: root.boot()
}
