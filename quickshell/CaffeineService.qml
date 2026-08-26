pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Caffeine — "keep this machine awake" — as ONE piece of state the whole shell reads.
//
// The toggle used to be a shell script and nothing else: assets/scripts/caffeine.sh holds a
// `systemd-inhibit --what=idle` process, and that worked as long as hypridle owned the idle chain,
// because hypridle honours systemd inhibitors. The chain has since moved into the shell
// (IdleService, ext-idle-notify-v1) and HYPRLAND HAS NO LOGIND INTEGRATION AT ALL — there is not a
// single login1 idle symbol in the binary. So the switch quietly stopped doing the one thing it is
// for: caffeine was on, and the screensaver, the lock and the suspend all still fired.
//
// The script stays the source of truth (its state is a running process, so it survives a shell
// restart and a CLI toggle is seen too), and this singleton is what the shell reads: IdleService
// gates its three stages on `active`, so keep-awake means keep-awake again.
Singleton {
    id: root

    property bool active: false

    readonly property string _sh: (Quickshell.env("VELUMERON_DIR") ?? "") + "/assets/scripts/caffeine.sh"

    readonly property Process _get: Process {
        stdout: SplitParser { onRead: line => root.active = ("" + line).trim() === "on" }
    }
    readonly property Process _set: Process {
        // Re-read rather than trust the click: the script is also reachable from the CLI, and the
        // process it starts may fail.
        onRunningChanged: if (!running) root.refresh()
    }

    function refresh() {
        root._get.command = ["bash", root._sh, "--active"]
        root._get.running = false
        root._get.running = true
    }
    function toggle() { root._run("--toggle") }
    function set(on)  { root._run(on ? "--on" : "--off") }
    function _run(arg) {
        root._set.command = ["bash", root._sh, arg]
        root._set.running = false
        root._set.running = true
    }

    // A toggle from outside the shell (the CLI, the settings hub's own call) shows up within a few
    // seconds; nothing here is hot enough to poll faster.
    readonly property Timer _poll: Timer {
        interval: 5000; repeat: true; running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
