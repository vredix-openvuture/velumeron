// Live list of open Hyprland windows (toplevels) for the taskbar OSD and the window tags. Quickshell's
// Hyprland module has no live toplevel model in this build, so we query `hyprctl clients -j` and
// re-query (debounced) whenever a relevant window event fires. The active window's address is tracked
// from activewindowv2 so focus highlights update instantly. While window tags are enabled a gentle
// poll additionally keeps geometry fresh (interactive move/resize emits no events) and tracks the
// cursor for the proximity fade. One shared singleton feeds every per-screen surface.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: root

    // [{ address, cls, title, monitorId, workspace, floating, focused, x, y, w, h, fs }] in global
    // layout coordinates, stable order (by address).
    property var    windows:    []
    property string activeAddr: ""
    property string _lastJson:  ""

    // Global cursor position (layout coords), polled only while window tags are enabled.
    property real cursorX: -99999
    property real cursorY: -99999

    // Hyprland's window corner radius (decoration:rounding) — the window tags follow it so a corner
    // tag hugs the window silhouette. Queried once at startup and again on config reload.
    property int rounding: 0
    readonly property Process _roundProc: Process {
        command: ["bash", "-c", "hyprctl getoption decoration:rounding -j | tr -d '\\n'"]
        stdout: SplitParser {
            onRead: line => {
                try { root.rounding = JSON.parse(line).int ?? 0 } catch (e) { /* keep previous */ }
            }
        }
    }
    function _queryRounding() { _roundProc.running = false; _roundProc.running = true }

    // ── Window-tags poll: geometry freshness (drags/resizes fire no events) + cursor tracking ────
    readonly property Timer _tagPoll: Timer {
        interval: 200; repeat: true
        running: VtlConfig.windowTagsAnyEnabled
        onTriggered: { root._pollCursor(); root._query() }
    }
    readonly property Process _curProc: Process {
        command: ["hyprctl", "cursorpos"]
        stdout: SplitParser {
            onRead: line => {
                var p = ("" + line).split(",")
                if (p.length >= 2) { root.cursorX = parseFloat(p[0]); root.cursorY = parseFloat(p[1]) }
            }
        }
    }
    function _pollCursor() { _curProc.running = false; _curProc.running = true }

    // ── "A real fullscreen window covers this monitor" ───────────────────────────────────────────
    // The bar-docked surfaces (flyouts, settings menu, notif centre, OSD, taskbar) need to know
    // whether the bar is actually hidden, so they either dock onto its inner face or grow from the
    // bare screen edge. Hyprland's raw "fullscreen>>0/1" event is the wrong source for that in three
    // ways: it also fires for MAXIMIZED windows (mode 1 — those respect the exclusive zone, the bar
    // stays visible), it carries no monitor/workspace, and nothing resets it when you switch away
    // from (or close) the fullscreen window. A latched flag made every popout believe the bar was
    // gone and draw ON TOP of it. Derive the state from the live client list instead: mode 2 only,
    // on THIS monitor's ACTIVE workspace. The bar sits on the Bottom layer, so exactly that case
    // hides it.
    property var fsMons: ({})     // { monitorId: true } — monitors whose bar is covered right now
    function fullscreenOn(monId) { return monId >= 0 && root.fsMons[monId] === true }
    function _recheckFullscreen() {
        var out  = {}
        var mons = Hyprland.monitors ? Hyprland.monitors.values : []
        var all  = root.windows
        for (var i = 0; i < mons.length; i++) {
            var m = mons[i]
            if (!m) continue
            var wsId = m.activeWorkspace ? m.activeWorkspace.id : -999
            for (var j = 0; j < all.length; j++)
                if (all[j].fsMode === 2 && all[j].monitorId === m.id && all[j].workspace === wsId) {
                    out[m.id] = true
                    break
                }
        }
        // Only publish real changes — consumers bind on this and shouldn't churn on every re-query.
        var s = JSON.stringify(out)
        if (s === root._lastFsJson) return
        root._lastFsJson = s
        root.fsMons = out
    }
    property string _lastFsJson: "{}"

    // ── "Which special workspace is pulled out on this monitor" ──────────────────────────────────
    // A scratchpad renders ABOVE the normal workspace's windows but keeps its own (negative)
    // workspace id, and the monitor's activeWorkspace still names the normal one — so anything that
    // decides what's visible by comparing against activeWorkspace alone misses it entirely. The
    // window tags did, and the windows underneath kept their chips, which then floated on top of the
    // scratchpad window with someone else's name on them. Tracked from `hyprctl monitors -j`, which
    // is the only place the shown special workspace is stated; it changes on activespecial and
    // nowhere else, so this is event-driven and never polled.
    property var specialWs: ({})        // { monitorId: wsId } — only monitors with one pulled out
    function specialWsOn(monId) {
        var v = root.specialWs[monId]
        return v === undefined ? 0 : v          // 0 = none (no real window ever has workspace 0)
    }
    property string _lastSpecialJson: "{}"
    readonly property Process _monProc: Process {
        property string _acc: ""
        stdout: SplitParser { onRead: line => { _monProc._acc += line } }
        onRunningChanged: if (!running) { root._parseMonitors(_monProc._acc); _monProc._acc = "" }
    }
    function _queryMonitors() {
        _monProc._acc = ""
        _monProc.command = ["bash", "-c", "hyprctl monitors -j | tr -d '\\n\\r'"]
        _monProc.running = false; _monProc.running = true
    }
    function _parseMonitors(txt) {
        var out = {}
        try {
            var arr = JSON.parse(("" + txt).trim())
            for (var i = 0; i < arr.length; i++) {
                var sw = arr[i].specialWorkspace
                if (sw && sw.id !== 0) out[arr[i].id] = sw.id
            }
        } catch (e) { return }                  // keep the previous map on a garbled read
        var s = JSON.stringify(out)
        if (s === root._lastSpecialJson) return
        root._lastSpecialJson = s
        root.specialWs = out
    }
    // A workspace switch changes which windows are visible without changing the client list, and the
    // monitor graph may not have caught up yet when the event lands → re-check now AND after it settles.
    readonly property Timer _fsSettle: Timer { interval: 200; repeat: false; onTriggered: root._recheckFullscreen() }

    // ── Re-query on window events (debounced) ────────────────────────────────────────────────────
    readonly property Timer _debounce: Timer { interval: 120; repeat: false; onTriggered: root._query() }
    readonly property Connections _ev: Connections {
        target: Hyprland
        function onRawEvent(event) {
            var n = event.name
            if (n === "fullscreen" || n === "workspacev2" || n === "focusedmon" || n === "activespecial"
                || n === "monitoraddedv2" || n === "monitorremoved" || n === "closewindow"
                || n === "movewindowv2") {
                root._recheckFullscreen()
                root._fsSettle.restart()
            }
            // Only the events that can actually change WHICH special workspace is out — notably
            // not focusedmon, which fires on every cursor crossing between monitors.
            if (n === "activespecial" || n === "activespecialv2"
                || n === "monitoraddedv2" || n === "monitorremoved")
                root._queryMonitors()
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
            if (n === "configreloaded") root._queryRounding()
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
                    pinned:    !!w.pinned,
                    // Focus recency (0 = focused) — the tags use it as a z-order heuristic to hide
                    // chips covered by a more recently raised float.
                    fhi:       (w.focusHistoryID !== undefined ? w.focusHistoryID : 999),
                    focused:   w.address === root.activeAddr,
                    x: (w.at ? w.at[0] : 0), y: (w.at ? w.at[1] : 0),
                    w: (w.size ? w.size[0] : 0), h: (w.size ? w.size[1] : 0),
                    fs: !!w.fullscreen,
                    fsMode: (w.fullscreen || 0)   // 0 none · 1 maximized · 2 real fullscreen
                }
            })
        } catch (e) { out = [] }
        // Skip the reassignment when nothing changed, so the 200ms tag poll doesn't churn every
        // consumer (Repeater models would rebuild their delegates each tick).
        var s = JSON.stringify(out)
        if (s !== root._lastJson) { root._lastJson = s; root.windows = out }
        root._recheckFullscreen()
    }
    // Update just the focused flag in place (fast path for activewindowv2).
    function _markFocused() {
        var ws = root.windows.slice()
        for (var i = 0; i < ws.length; i++) ws[i] = Object.assign({}, ws[i], { focused: ws[i].address === root.activeAddr })
        root._lastJson = JSON.stringify(ws)
        root.windows = ws
    }

    Component.onCompleted: { root._query(); root._queryRounding(); root._queryMonitors() }
}
