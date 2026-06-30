import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: root

    // Fullscreen transparent overlay — same pattern as the Python GTK panel.
    visible:                      UiState.guiPanelOpen
    color:                        "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:          WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property string _vtlDir: Quickshell.env("VELUMERON_DIR") ?? ""

    // ── File-based IPC: velumeron quickshell --gui-panel writes the trigger ──
    Timer {
        interval: 200; repeat: true; running: true
        onTriggered: { ipcProc.running = false; ipcProc.running = true }
    }
    Process {
        id: ipcProc
        command: ["bash", "-c",
            "f=/tmp/velumeron-qs-gui-panel; [ -f \"$f\" ] && rm \"$f\" && echo 1"]
        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "1") UiState.guiPanelOpen = !UiState.guiPanelOpen
            }
        }
    }

    // ── Outside click closes panel (same as Python click-catcher) ────────────
    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: UiState.guiPanelOpen = false
    }

    Shortcut { sequence: "Escape"; onActivated: UiState.guiPanelOpen = false }

    // ── Panel (left-anchored, full height) ───────────────────────────────────
    Rectangle {
        id: panel
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: 700
        color: Colors.bgPrimary
        z: 1

        MouseArea { anchors.fill: parent }  // block click-through

        Row {
            anchors.fill: parent
            spacing: 0

            // ── Sidebar (logo + nav) ─────────────────────────────────────
            Rectangle {
                id: sidebar
                width: 56
                height: parent.height
                color: Colors.bgElement

                // Logo
                Image {
                    anchors { top: parent.top; topMargin: 18; horizontalCenter: parent.horizontalCenter }
                    source:   "file://" + root._vtlDir + "/assets/icons/vuture.png"
                    width:    28
                    height:   28
                    fillMode: Image.PreserveAspectFit
                }

                // Nav buttons (stacked below logo)
                Column {
                    anchors { top: parent.top; topMargin: 64; left: parent.left; right: parent.right }
                    spacing: 2

                    // Bar page button
                    NavBtn { icon: ""; tooltip: "Bar"; pageId: "bar"; activePage: root.activePage; onActivate: root.activePage = "bar" }
                }

                // Bottom separator + future Settings / Info buttons
                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 1
                    color:  Colors.boNormal
                    opacity: 0.4
                }
            }

            // ── Content area ─────────────────────────────────────────────
            Rectangle {
                width:  panel.width - sidebar.width
                height: parent.height
                color:  Colors.bgPrimary

                BarPage { anchors.fill: parent }
            }
        }
    }

    // ── Active page state ────────────────────────────────────────────────────
    property string activePage: "bar"

    // ── Inline nav button component ──────────────────────────────────────────
    component NavBtn: Rectangle {
        id: navBtn
        property string icon:       ""
        property string tooltip:    ""
        property string pageId:     ""
        property string activePage: ""
        signal activate()

        width:  56
        height: 44
        color:  (activePage === pageId)
                ? Colors.bgActive
                : (hov.containsMouse
                   ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18)
                   : "transparent")

        Text {
            anchors.centerIn: parent
            text:           navBtn.icon
            color:          (navBtn.activePage === navBtn.pageId) ? Colors.fgBright : Colors.fgMuted
            font.pixelSize: 17
            font.family:    "FantasqueSansM Nerd Font"
        }

        MouseArea {
            id: hov; anchors.fill: parent; hoverEnabled: true
            onClicked: navBtn.activate()
        }
    }
}
