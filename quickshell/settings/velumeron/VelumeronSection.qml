import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Velumeron itself — the shell as a running program, plus the portable backup of its configuration.
//
// SHELL: what the process is doing right now (uptime, memory, render loop) and the two buttons that
// act on it. Restarting used to mean a terminal; it belongs here, because a cold start is what
// picks up edited QML — the shell compiles a component once and keeps it.
// IMPORT / EXPORT: a single-file backup of the effective settings, the wallust palette options and
// the themes you made yourself. All the file work lives in assets/scripts/settings-backup.py; this page
// only picks a path with the native zenity dialog and reports the result. Device-bound keys
// (monitors / bluetooth / per-monitor wallpaper folders) are always re-taken from THIS machine on
// import, so restoring a foreign export is safe.
Item {
    id: root

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

    property string status: ""
    property bool   ok:     true
    Timer { id: clear; interval: 5000; onTriggered: root.status = "" }
    function _say(msg, good) { root.status = msg; root.ok = good; clear.restart() }

    // ── Shell runtime ───────────────────────────────────────────────────────────────────────────
    property int    pid:    0
    property int    upSecs: 0
    property int    rssKb:  0
    readonly property string upText: {
        if (root.upSecs <= 0) return "—"
        var d = Math.floor(root.upSecs / 86400)
        var h = Math.floor((root.upSecs % 86400) / 3600)
        var m = Math.floor((root.upSecs % 3600) / 60)
        if (d > 0) return d + " d " + h + " h"
        if (h > 0) return h + " h " + m + " min"
        return m + " min"
    }
    readonly property string memText: root.rssKb > 0
                                      ? (root.rssKb / 1024).toFixed(0) + " MB" : "—"
    // pid / seconds-of-uptime / resident memory, straight from ps — one call, no polling of /proc.
    Process {
        id: statProc
        command: ["bash", "-c",
                  "p=$(pgrep -x quickshell | head -1); [ -n \"$p\" ] && ps -o pid=,etimes=,rss= -p \"$p\""]
        stdout: SplitParser {
            onRead: line => {
                var f = ("" + line).trim().split(/\s+/)
                if (f.length < 3) return
                root.pid    = parseInt(f[0]) || 0
                root.upSecs = parseInt(f[1]) || 0
                root.rssKb  = parseInt(f[2]) || 0
            }
        }
    }
    function refresh() { statProc.running = false; statProc.running = true }
    Component.onCompleted: root.refresh()
    onVisibleChanged: if (visible) root.refresh()
    Timer { interval: 5000; repeat: true; running: root.visible; onTriggered: root.refresh() }

    // Restarting kills the process this page lives in, so the launcher has to survive it: `setsid`
    // puts it in its own session, out of reach of the pkill inside the script.
    Process { id: restartProc }
    function restartShell() {
        restartProc.command = ["bash", "-c",
            "setsid -f \"$VELUMERON_DIR/assets/scripts/launch-quickshell.sh\" >/dev/null 2>&1"]
        restartProc.running = false; restartProc.running = true
    }
    Process { id: reloadProc; command: ["hyprctl", "reload"] }

    // Two-step, because the first click of a mis-click shouldn't take the desktop's chrome with it.
    property bool armed: false
    Timer { id: disarm; interval: 4000; onTriggered: root.armed = false }

    // ── Export / import ─────────────────────────────────────────────────────────────────────────
    function doExport() {
        UiState.pickerOpen = true
        // settings_YY-MM-DD.velbak — the date is in the name so a folder of backups sorts itself.
        exportProc.command = ["bash", "-c",
            "p=$(zenity --file-selection --save --confirm-overwrite " +
            "--filename=\"$HOME/settings_$(date +%y-%m-%d).velbak\" --title='Export Velumeron settings' 2>/dev/null) " +
            "|| exit 0; [ -n \"$p\" ] && python3 \"$VELUMERON_DIR/assets/scripts/settings-backup.py\" export \"$p\""]
        exportProc.running = false; exportProc.running = true
    }
    Process {
        id: exportProc
        stdout: SplitParser { onRead: line => {
            var t = ("" + line).trim()
            if (t.indexOf("export:ok:") === 0)
                root._say("Exported to " + t.slice(10), true)
        } }
        onRunningChanged: if (!running) UiState.pickerOpen = false
    }

    function doImport() {
        UiState.pickerOpen = true
        importProc.command = ["bash", "-c",
            // Older exports carry .json, so they stay selectable next to the current .velbak.
            "p=$(zenity --file-selection --title='Import Velumeron settings' " +
            "--file-filter='Velumeron backup | *.velbak *.json' 2>/dev/null) " +
            "|| exit 0; [ -n \"$p\" ] && python3 \"$VELUMERON_DIR/assets/scripts/settings-backup.py\" import \"$p\""]
        importProc.running = false; importProc.running = true
    }
    Process {
        id: importProc
        stdout: SplitParser { onRead: line => {
            var t = ("" + line).trim()
            if (t === "import:ok")           root._imported = true
            else if (t === "import:invalid") root._say("Not a Velumeron backup file.", false)
        } }
        property bool _imported: false
        onRunningChanged: {
            if (running) { _imported = false; return }
            UiState.pickerOpen = false
            if (_imported) {
                Theme.refresh()              // pick up restored themes
                root._say("Settings imported — applied live.", true)
            }
        }
    }

    // Label on the left, live value on the right — the read-only counterpart of a Stepper row.
    component InfoRow: Item {
        property string label: ""
        property string value: ""
        width: parent ? parent.width : 0
        height: 24
        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: parent.label; color: Colors.fgPrimary
            font.pixelSize: Style.fsLabel; font.family: Style.font
        }
        Text {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: parent.value; color: Colors.fgBright
            font.pixelSize: Style.fsValue; font.family: Style.font
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        CardColumns {
            id: col
            forced: root.pageCols
            firstRowMin: root.pageRowMin
            width: parent.width
            y: 4

            // ── Shell ─────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "SHELL"
                            hint: "The running shell process. A restart is what picks up edited QML: "
                                + "a component is compiled once and then kept, so changes to files "
                                + "already in use only appear after a cold start. Your windows and "
                                + "apps are untouched — only the bar, menus and overlays blink." }

                InfoRow { label: "Uptime";      value: root.upText }
                InfoRow { label: "Memory";      value: root.memText }
                InfoRow { label: "Process";     value: root.pid > 0 ? "PID " + root.pid : "not found" }
                InfoRow { label: "Render loop"; value: VtlConfig.lowMemoryMode ? "basic (low memory)" : "threaded" }

                Row {
                    width: parent.width; spacing: 8
                    TextButton {
                        primary: root.armed
                        label: root.armed ? "󰑓  Restart now" : "󰑓  Restart shell"
                        onClicked: {
                            if (!root.armed) { root.armed = true; disarm.restart(); return }
                            root.armed = false; disarm.stop()
                            root.restartShell()
                        }
                    }
                    TextButton {
                        label: "󰜉  Reload Hyprland"
                        onClicked: { reloadProc.running = false; reloadProc.running = true
                                     root._say("Hyprland config reloaded.", true) }
                    }
                }
                SubLabel {
                    width: parent.width
                    visible: root.armed
                    color: Colors.fgUrgent
                    text: "Click again to restart — the bar and every menu go away for a moment."
                }
            }

            // ── Startup ───────────────────────────────────────────────────────
            Card {
                CardLabel { text: "STARTUP"
                            hint: "A curtain over the shell's own start-up — wallpaper, bar and tray "
                                + "all pop in within the first second, and that popping is what looks "
                                + "broken. Plays on every start, login and restart alike." }
                Toggle {
                    label: "Splash screen"
                    sub:   "Cover the shell's start — every time it starts"
                    on:    VtlConfig.splashEnabled
                    onToggled: SettingsStore.set("splash_enabled", !VtlConfig.splashEnabled)
                }
                Slider {
                    visible: VtlConfig.splashEnabled
                    label: "Duration"; from: 0.8; to: 8.0; decimals: 1; step: 0.1; labelWidth: 70
                    value: VtlConfig.splashSeconds
                    onMoved: (v) => SettingsStore.set("splash_seconds", v)
                }
                SubLabel {
                    visible: VtlConfig.splashEnabled
                    width: parent.width
                    text: "Total time on screen. The wordmark lights up over that span and the curtain tears open the moment it is full."
                }
                TextButton {
                    visible: VtlConfig.splashEnabled
                    label: "󰐊  Preview splash"
                    onClicked: { UiState.openDropdown = ""; SplashState.replay() }
                }
            }

            // ── Export ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "EXPORT"
                            hint: "Save your whole configuration — settings, colour options and your custom styles — to a single file you can back up or move to another machine." }
                TextButton { primary: true; label: "󰆓  Export settings…"; onClicked: root.doExport() }
            }

            // ── Import ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "IMPORT"
                            hint: "Load a previously exported file. It replaces your current settings and applies live. Hardware-bound bits (monitors, Bluetooth, per-monitor wallpaper folders) stay as they are on this machine." }
                TextButton { label: "󰉚  Import settings…"; onClicked: root.doImport() }
            }

            // ── Result ────────────────────────────────────────────────────────
            Text {
                property bool spans: true    // a lead-in line, not a card
                width: parent.width
                visible: root.status !== ""
                text: root.status
                color: root.ok ? Colors.fgPrimary : Colors.fgUrgent
                font.pixelSize: Style.fsSub; font.family: Style.font
                wrapMode: Text.Wrap
            }
        }
    }
}
