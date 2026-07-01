// Live list of open Hyprland windows (toplevels) for the taskbar OSD. Quickshell's Hyprland module
// has no live toplevel model in this build, so we query `hyprctl clients -j` and re-query (debounced)
// whenever a relevant window event fires. The active window's address is tracked from activewindowv2
// so focus highlights update instantly. One shared singleton feeds every per-screen Taskbar surface.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: root

    // [{ address, cls, title, monitorId, workspace, floating, focused }], stable order (by address).
    property var    windows:    []
    property string activeAddr: ""

    // ── Re-query on window events (debounced) ────────────────────────────────────────────────────
    readonly property Timer _debounce: Timer { interval: 120; repeat: false; onTriggered: root._query() }
    readonly property Connections _ev: Connections {
        target: Hyprland
        function onRawEvent(event) {
            var n = event.name
            if (n === "activewindowv2") {
                var a = ("" + event.data).trim()
                root.activeAddr = (a.indexOf("0x") === 0) ? a : ("0x" + a)
                root._markFocused()          // instant highlight; a re-query follows for the rest
                root._debounce.restart()
                return
            }
            if (n === "openwindow" || n === "closewindow" || n === "movewindowv2" || n === "windowtitlev2"
                || n === "urgent" || n === "changefloatingmode" || n === "fullscreen" || n === "workspacev2"
                || n === "renameworkspace")
                root._debounce.restart()
        }
    }

    readonly property Process _proc: Process {
        property string _acc: ""
        stdout: SplitParser { onRead: line => { _proc._acc += line } }
        onRunningChanged: if (!running) { root._parse(_proc._acc); _proc._acc = "" }
    }
    function _query() {
        _proc._acc = ""
        _proc.command = ["bash", "-c", "hyprctl clients -j | tr -d '\\n\\r'"]
        _proc.running = false; _proc.running = true
    }

    function _parse(txt) {
        var out = []
        try {
            var arr = JSON.parse(("" + txt).trim())
            arr = arr.filter(function (w) { return w && !w.hidden && w.mapped !== false && w.address })
            // Stable order (by address) so items don't jump around as focus changes.
            arr.sort(function (a, b) { return a.address < b.address ? -1 : a.address > b.address ? 1 : 0 })
            out = arr.map(function (w) {
                return {
                    address:   w.address,
                    cls:       (w.class || ""),
                    title:     (w.title || w.class || "Window"),
                    monitorId: (w.monitor !== undefined ? w.monitor : -1),
                    workspace: (w.workspace ? w.workspace.id : -1),
                    floating:  !!w.floating,
                    focused:   w.address === root.activeAddr
                }
            })
        } catch (e) { out = [] }
        root.windows = out
    }
    // Update just the focused flag in place (fast path for activewindowv2).
    function _markFocused() {
        var ws = root.windows.slice()
        for (var i = 0; i < ws.length; i++) ws[i] = Object.assign({}, ws[i], { focused: ws[i].address === root.activeAddr })
        root.windows = ws
    }

    Component.onCompleted: root._query()
}
