pragma Singleton
import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// Shared state for the FancyZones overlay. modules/fancyzones.lua (the compositor side)
// pokes `zones open` / `zones close` over IPC while a floating window is Super-dragged;
// while active, the global cursor position is polled so every ZoneOverlay can highlight
// the zone under the cursor. (The overlay is input-transparent during the drag, so the
// cursor can't be tracked with a MouseArea — polling hyprctl is the only live source.)
//
// This singleton also WRITES the zone state file the Lua side snaps from: fancyzones.lua
// runs inside the compositor, where calling `hyprctl`/`jq` via io.popen blocks Hyprland
// itself (the release handler froze the session for the subprocess round-trip). So all
// the data Lua needs — enabled, gap, zone fractions, and each monitor's usable area in
// global logical pixels — is pre-written here and Lua does a plain io.open read.
Singleton {
    id: root

    property bool active: false
    property real cx: -1e9   // global (layout) coords; far off-screen while unknown
    property real cy: -1e9

    // Hyprland invokes mouse binds on press AND release, so right after the release bind's
    // snap+close the press wrapper can fire once more and re-open the overlay — which then
    // sat on screen until the failsafe. The Lua side guards against that, and this cooldown
    // catches the remaining ordering (snap ran first and already cleared the drag flag).
    property double _closedAt: 0
    // show() also refreshes the state file, so the Lua side always snaps against current geometry.
    function show() {
        if (Date.now() - root._closedAt < 400) return
        root.active = true
        writeDebounce.restart()
    }
    function hide() {
        root._closedAt = Date.now()
        root.active = false; root.cx = -1e9; root.cy = -1e9
    }

    // ── Zone state file for modules/fancyzones.lua ────────────────────────────────
    readonly property string statePath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/velumeron-zones.state"

    readonly property string stateContent: {
        var lines = ["enabled " + (VtlConfig.fancyZonesEnabled ? "true" : "false"),
                     "gap " + VtlConfig.fancyZonesGap,
                     "zones " + VtlConfig.fancyZonesResolved]
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; i++) {
            var s = screens[i]
            var u = VtlConfig.lockRect(s.name, s.width, s.height)
            // Trailing token: this monitor's zone layout (per-monitor override or the global one).
            lines.push("mon " + s.name + " " + Math.round(s.x + u[0]) + " " + Math.round(s.y + u[1])
                       + " " + Math.round(u[2]) + " " + Math.round(u[3])
                       + " " + VtlConfig.fancyZonesResolvedFor(s.name))
        }
        return lines.join("\n") + "\n"
    }
    // Rewrite (debounced) whenever settings, bar geometry or the monitor set change.
    onStateContentChanged: writeDebounce.restart()
    readonly property Timer _writeDebounce: Timer {
        id: writeDebounce
        interval: 250
        onTriggered: {
            writeProc.command = ["python3", "-c",
                "import sys; open(sys.argv[1], 'w').write(sys.argv[2])",
                root.statePath, root.stateContent]
            writeProc.running = false
            writeProc.running = true
        }
    }
    readonly property Process _writeProc: Process { id: writeProc }
    Component.onCompleted: writeDebounce.restart()

    Process {
        id: posProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = ("" + text).trim().match(/(-?\d+),\s*(-?\d+)/)
                if (m) { root.cx = +m[1]; root.cy = +m[2] }
            }
        }
    }
    Timer {
        interval: 50; repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: { posProc.running = false; posProc.running = true }
    }

    // Safety: a missed `hide` must not leave the overlay on screen. Cursor movement (an
    // active drag) keeps rearming it, so it only fires once the pointer has been still for
    // a while with the overlay inexplicably open — never mid-drag, however long it takes.
    Timer {
        id: failsafe
        interval: 8000
        running: root.active
        onTriggered: root.hide()
    }
    onCxChanged: if (root.active) failsafe.restart()
}
