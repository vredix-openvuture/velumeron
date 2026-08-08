pragma Singleton
import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// Paired phones and tablets, through KDE Connect — but never through any KDE window. The daemon is
// the only part of KDE Connect involved; assets/scripts/kdeconnect.py talks to it over D-Bus and
// prints JSON, and everything the user sees is rendered by the shell.
//
// The daemon is D-Bus activatable, so "not running" and "not installed" look the same from here:
// `available` is false either way and the module keeps out of the bar rather than showing a dead
// icon. Polling instead of watching signals is deliberate — dbus-python in a one-shot script has
// nothing to subscribe with, and a phone's battery does not need sub-minute news.
Singleton {
    id: root

    property var  data: ({ available: false, error: "", devices: [] })
    property bool busy: false

    readonly property string script: Quickshell.env("VELUMERON_DIR") + "/assets/scripts/kdeconnect.py"

    readonly property bool available: data.available === true
    readonly property var  devices:   data.devices ?? []
    readonly property var  reachable: root.devices.filter(d => d.reachable && d.paired)
    readonly property bool hasDevices: root.reachable.length > 0

    // The device the bar module speaks for: the first reachable phone, else the first reachable
    // anything, so a tablet doesn't outrank the phone just by sorting first.
    readonly property var primary: {
        var rs = root.reachable
        for (var i = 0; i < rs.length; i++) if (rs[i].type === "phone") return rs[i]
        return rs.length > 0 ? rs[0] : null
    }

    function deviceById(id) {
        var ds = root.devices
        for (var i = 0; i < ds.length; i++) if (ds[i].id === id) return ds[i]
        return null
    }
    function hasPlugin(d, name) {
        return !!(d && d.plugins && d.plugins.indexOf("kdeconnect_" + name) >= 0)
    }
    function icon(d) {
        if (!d) return "󰄜"
        return d.type === "tablet" ? "󰓶" : d.type === "laptop" || d.type === "desktop" ? "󰌢" : "󰄜"
    }
    // Signal bars for the cellular strength KDE Connect reports (0…4).
    function signalGlyph(s) {
        if (s === undefined || s === null || s < 0) return ""
        return ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"][Math.max(0, Math.min(4, s))]
    }

    // ── Refresh ────────────────────────────────────────────────────────────────────────────────
    Process {
        id: listProc
        property string _acc: ""
        command: ["python3", root.script, "list"]
        stdout: SplitParser { onRead: line => { listProc._acc += line } }
        onRunningChanged: if (!running) {
            var t = listProc._acc.trim()
            listProc._acc = ""
            root.busy = false
            if (t === "") return
            try {
                var d = JSON.parse(t)
                if (d && typeof d === "object") root.data = d
            } catch (e) { /* keep the last good state */ }
        }
    }
    function refresh() {
        if (listProc.running) return
        root.busy = true
        listProc._acc = ""
        listProc.running = true
    }

    // Slow while nobody is looking, brisk while a surface is showing it. `watchers` is incremented
    // by any open popout — a phone's battery is not worth a subprocess every few seconds otherwise.
    property int watchers: 0
    Timer {
        // Watched → brisk. Idle with a daemon → once a minute. No daemon at all → back off hard;
        // a shell that runs for days shouldn't spawn a python process every minute to re-learn
        // that KDE Connect still isn't installed.
        interval: root.watchers > 0 ? 5000 : (root.available ? 60000 : 300000)
        repeat:   true
        running:  true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // ── Actions ────────────────────────────────────────────────────────────────────────────────
    Process { id: actProc; onRunningChanged: if (!running) root.refresh() }
    function _act(args) {
        actProc.command = ["python3", root.script].concat(args)
        actProc.running = false
        actProc.running = true
    }
    function ring(id)          { root._act(["ring", id]) }
    function ping(id)          { root._act(["ping", id, "Velumeron"]) }
    function shareText(id, t)  { root._act(["share-text", id, t]) }
    function share(id, paths) {
        if (!paths || paths.length === 0) return
        root._act(["share"].concat([id]).concat(paths))
    }

    // Pick files and send them — the AirDrop gesture, without a KDE window anywhere in it. The
    // chooser is zenity (GTK, already on the system); its output is one path per line.
    property string _pickFor: ""
    Process {
        id: pickProc
        property string _acc: ""
        stdout: SplitParser { onRead: line => { pickProc._acc += line + "\n" } }
        onRunningChanged: if (!running) {
            var lines = pickProc._acc.split("\n").filter(s => s.trim() !== "")
            pickProc._acc = ""
            if (lines.length > 0 && root._pickFor !== "") root.share(root._pickFor, lines)
            root._pickFor = ""
        }
    }
    function pickAndShare(id) {
        if (pickProc.running) return
        root._pickFor = id
        pickProc._acc = ""
        pickProc.command = ["python3", root.script, "pick"]
        pickProc.running = true
    }
}
