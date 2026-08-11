import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// Runs the capture. Nothing visual, no window, no surface — which is the entire point.
//
// This used to live inside ShotOverlay: the picker armed a mode, closed itself, and a Timer *inside
// the closing window* fired the script. That works only as long as the overlay is immortal, and the
// overlay had to be immortal only because the capture depended on it. Now the picker is disposable —
// it can be built on demand and destroyed on close — because the thing that outlives it is this,
// forty lines of QtObject that cost nothing to keep alive.
//
// The channel is UiState.shotFire: write a mode into it and a capture happens, whether the picker
// was ever on screen or not. That is also what makes `velumeron --screenshot region` work with no UI
// at all.
QtObject {
    id: runner

    // A beat for the picker's surface to actually go away before grim looks at the screen — it
    // would photograph the picker, and slurp would be fighting it for the pointer.
    // Longer than the picker's 180 ms fade, shorter than shell.qml's 320 ms linger: by the time
    // this fires the surface is unmapped but the object is still alive, which is the window in
    // which it is safe to photograph the screen.
    readonly property int settleMs: 260

    property string _mode: ""

    readonly property Process _proc: Process { }

    readonly property Timer _settle: Timer {
        interval: runner.settleMs
        onTriggered: {
            var m = runner._mode
            runner._mode = ""
            if (m === "") return

            var a = [Quickshell.env("VELUMERON_DIR") + "/assets/scripts/screenshot.sh", m]
            if (m === "window" && UiState.shotGeom !== "") { a.push("--geom");   a.push(UiState.shotGeom) }
            if (m === "output" && UiState.shotMon  !== "") { a.push("--output"); a.push(UiState.shotMon) }
            if (!VtlConfig.shotCopy) a.push("--no-copy")
            if (!VtlConfig.shotSave) a.push("--no-save")
            if (VtlConfig.shotDelay > 0) { a.push("--delay"); a.push("" + VtlConfig.shotDelay) }

            // One line per capture. A screenshot tool is the one thing you cannot debug by taking a
            // screenshot of it, and this path has cost enough guesses already.
            console.warn("screenshot: " + a.slice(1).join(" "))
            runner._proc.command = ["setsid", "bash"].concat(a)
            runner._proc.running = false
            runner._proc.running = true
        }
    }

    readonly property Connections _watch: Connections {
        target: UiState
        function onShotFireChanged() {
            if (UiState.shotFire === "") return
            runner._mode = UiState.shotFire
            UiState.shotFire = ""              // consume it, so the same mode can be asked for twice
            // Closing the picker from HERE, not from inside the picker's own click handler.
            UiState.shotOpen = false
            runner._settle.restart()
        }
    }
}
