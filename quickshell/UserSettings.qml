pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The ONE QML gateway to user_settings.lua (device config: monitors, workspaces, autostart,
// quick access, peripherals, window rules, role apps). Mirrors SettingsStore's role for
// gui/settings.json — sections talk JSON to assets/scripts/user-settings-io.py, never to the
// Lua file directly. Reads and writes are queued separately so rapid interactions can't
// interleave, and a write never cancels an in-flight one.
Singleton {
    id: root

    // ok=false carries the validator messages; sections show errors[0].
    signal sectionSaved(string section, bool ok, var errors)

    readonly property string _io: "\"$VELUMERON_DIR/assets/scripts/user-settings-io.py\""

    // ── get(section, callback) — callback receives the parsed object or null ──
    property var _getQ: []
    property var _curGet: null
    property string _getBuf: ""
    function get(section, cb) {
        root._getQ.push({ section: section, cb: cb })
        _pumpGet()
    }
    function _pumpGet() {
        if (getProc.running || root._getQ.length === 0) return
        root._curGet = root._getQ.shift()
        root._getBuf = ""
        getProc.command = ["bash", "-c", "python3 " + root._io + " get " + root._curGet.section]
        getProc.running = true
    }
    Process {
        id: getProc
        stdout: SplitParser { onRead: line => root._getBuf += line }
        onExited: {
            var cur = root._curGet
            root._curGet = null
            var obj = null
            try { obj = JSON.parse(root._getBuf) } catch (e) {}
            if (cur && cur.cb) cur.cb(obj)
            Qt.callLater(root._pumpGet)
        }
    }

    // ── set(section, obj, {noReload}) / reload() ──
    property var _setQ: []
    property var _curSet: null
    property string _setBuf: ""
    function set(section, obj, opts) {
        root._setQ.push({ section: section, json: JSON.stringify(obj),
                          noReload: !!(opts && opts.noReload) })
        _pumpSet()
    }
    // The one batched hyprctl reload after several set(…, {noReload:true}) calls.
    function reload() {
        root._setQ.push({ reload: true })
        _pumpSet()
    }
    function _pumpSet() {
        if (setProc.running || root._setQ.length === 0) return
        var job = root._setQ.shift()
        root._curSet = job
        root._setBuf = ""
        if (job.reload) {
            setProc.command = ["bash", "-c", "python3 " + root._io + " reload"]
        } else {
            setProc.command = ["bash", "-c",
                "printf %s \"$1\" | python3 " + root._io + " set " + job.section
                + (job.noReload ? " --no-reload" : ""),
                "vtl", job.json]
        }
        setProc.running = true
    }
    Process {
        id: setProc
        stdout: SplitParser { onRead: line => root._setBuf += line }
        onExited: exitCode => {
            var job = root._curSet
            root._curSet = null
            if (job && !job.reload) {
                var ok = exitCode === 0
                var errors = []
                try {
                    var r = JSON.parse(root._setBuf)
                    if (r.ok === false) ok = false
                    errors = r.errors || []
                    if (r.warning) errors = [r.warning]
                } catch (e) {}
                root.sectionSaved(job.section, ok, errors)
            }
            Qt.callLater(root._pumpSet)
        }
    }
}
