import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Import / Export — a portable single-file backup of the configuration (effective settings, wallust
// palette options, and private user templates). All the file work lives in assets/scripts/
// velumeron-config.py (export/import verbs); this page just picks a path with the native zenity
// dialog and reports the result. Device-bound keys (monitors / bluetooth / per-monitor wallpaper
// folders) are always re-taken from THIS machine on import, so restoring a foreign export is safe.
Item {
    id: root

    property string status: ""
    property bool   ok:     true
    Timer { id: clear; interval: 5000; onTriggered: root.status = "" }
    function _say(msg, good) { root.status = msg; root.ok = good; clear.restart() }

    // Export: zenity save dialog → CLI export. Prints "export:ok:<path>".
    function doExport() {
        UiState.pickerOpen = true
        exportProc.command = ["bash", "-c",
            "p=$(zenity --file-selection --save --confirm-overwrite " +
            "--filename=\"$HOME/velumeron-settings.json\" --title='Export Velumeron settings' 2>/dev/null) " +
            "|| exit 0; [ -n \"$p\" ] && python3 \"$VELUMERON_DIR/assets/scripts/velumeron-config.py\" export \"$p\""]
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

    // Import: zenity open dialog → CLI import. Prints "import:ok" or "import:invalid".
    function doImport() {
        UiState.pickerOpen = true
        importProc.command = ["bash", "-c",
            "p=$(zenity --file-selection --title='Import Velumeron settings' " +
            "--file-filter='Velumeron backup | *.json' 2>/dev/null) " +
            "|| exit 0; [ -n \"$p\" ] && python3 \"$VELUMERON_DIR/assets/scripts/velumeron-config.py\" import \"$p\""]
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
                Templates.refresh()          // pick up restored templates / active
                root._say("Settings imported — applied live.", true)
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            // ── Export ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "EXPORT" }
                SubLabel { width: parent.width
                           text: "Save your whole configuration — settings, colour options and your custom styles — to a single file you can back up or move to another machine." }
                TextButton { primary: true; label: "󰆓  Export settings…"; onClicked: root.doExport() }
            }

            // ── Import ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "IMPORT" }
                SubLabel { width: parent.width
                           text: "Load a previously exported file. It replaces your current settings and applies live. Hardware-bound bits (monitors, Bluetooth, per-monitor wallpaper folders) stay as they are on this machine." }
                TextButton { label: "󰉚  Import settings…"; onClicked: root.doImport() }
            }

            // ── Result ────────────────────────────────────────────────────────
            Text {
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
