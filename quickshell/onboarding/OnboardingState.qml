pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Drives the onboarding window: on shell boot it asks onboarding-state.py whether this is a
// fresh install (setup wizard), a package update (changelog report) or nothing. First-run
// waits until the --autostart bootstrap has written the MONITORS section before opening;
// update mode kicks off `welcome --sync --no-restart` in the background. finish() stamps the
// current version as seen — Skip stamps too, otherwise the wizard nags on every start.
Singleton {
    id: root

    property bool   open: false
    property string mode: "none"     // first-run | update
    property string mon:  ""         // latched monitor at open time
    property var    changelog: []
    property string currentVersion: ""
    property bool   forced: false    // opened via IPC — close() never stamps

    function boot() { _query("") }
    function openForced(m) {
        root.forced = true
        _query(m)
    }
    function finish() {
        markProc.running = false; markProc.running = true
        root.open = false
        root.forced = false
    }
    function close() {   // IPC close: just hide, don't stamp
        root.open = false
        root.forced = false
    }

    function _query(force) {
        stateProc.buf = ""
        stateProc.command = ["bash", "-c",
            (force !== "" ? "VELUMERON_ONBOARDING_FORCE=" + force + " " : "")
            + "python3 \"$VELUMERON_DIR/assets/scripts/onboarding-state.py\" state"]
        stateProc.running = false; stateProc.running = true
    }
    function _show(m) {
        root.mode = m
        root.mon = Hyprland.focusedMonitor?.name ?? ""
        root.page = 0
        root.open = true
    }

    // Wizard page index lives here so every per-screen window instance agrees.
    property int page: 0

    Process {
        id: stateProc
        property string buf: ""
        stdout: SplitParser { onRead: line => stateProc.buf += line }
        onExited: {
            var d = null
            try { d = JSON.parse(stateProc.buf) } catch (e) {}
            if (!d) return
            root.currentVersion = d.current || ""
            if (d.mode === "first-run") {
                root.changelog = []
                waitMon.tries = 0
                waitMon.start()
            } else if (d.mode === "update") {
                root.changelog = d.changelog || []
                if (!root.forced) syncProc.running = true
                root._show("update")
            }
        }
    }

    // First-run race: the shell can be up before `.setup/hyprland.sh --autostart` finished
    // writing the MONITORS section. Poll until a monitor exists (or give up blocking after
    // 90 s and open anyway — better a wizard with an empty workspace page than none).
    Timer {
        id: waitMon
        property int tries: 0
        interval: 1000; repeat: true
        onTriggered: {
            tries++
            if (tries > 90) { waitMon.stop(); root._show("first-run"); return }
            UserSettings.get("monitors", function (d) {
                if (d && d.monitors && d.monitors.length > 0 && waitMon.running) {
                    waitMon.stop()
                    root._show("first-run")
                }
            })
        }
    }

    // Update mode refreshes the user-dir templates in the background. --no-restart is
    // load-bearing: a shell restart here would re-run this whole check in a loop.
    Process {
        id: syncProc
        command: ["bash", "-c",
            "\"$VELUMERON_DIR/welcome_to_velumeron.sh\" --sync --no-restart >/dev/null 2>&1"]
    }

    Process {
        id: markProc
        command: ["bash", "-c",
            "python3 \"$VELUMERON_DIR/assets/scripts/onboarding-state.py\" mark-seen >/dev/null"]
    }
}
