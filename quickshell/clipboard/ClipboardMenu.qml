import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Clipboard history (replaces rofi/assets/clipvault.sh). A searchable list of clipvault entries over a
// dim backdrop; type to filter, arrows to move, Enter/click copies the entry back via wl-copy. One per
// screen; shows on the monitor focused at open (UiState.clipboardMon). Toggled via the `clipboard` IPC
// (Super+V). The `wl-paste --watch clipvault store` daemon (Hyprland autostart) fills the history.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool isOpen: UiState.clipboardOpen
    readonly property bool active: isOpen && root.mon !== "" && root.mon === UiState.clipboardMon

    property var items: []   // raw clipvault list lines
    readonly property var filtered: {
        var q = search.text.trim().toLowerCase()
        if (q === "") return root.items
        return root.items.filter(function (l) { return ("" + l).toLowerCase().indexOf(q) >= 0 })
    }
    onFilteredChanged: list.currentIndex = 0

    property real reveal: 0
    onActiveChanged: {
        reveal = active ? 1 : 0
        if (active) { search.text = ""; list.currentIndex = 0; root.load(); search.forceActiveFocus() }
    }
    Behavior on reveal { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    visible: active || root.reveal > 0.01

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    // Blur is opt-in (Settings → OSD): the -blur namespace gets a blur layer rule, the plain
    // one opts out of the global blur (layerrules.lua) so only the dim shade tints the screen.
    WlrLayershell.namespace:     VtlConfig.clipboardBlur ? "velumeron-clipboard-blur" : "velumeron-clipboard"
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusiveZone: 0

    Process {
        id: listProc
        property var _buf: []
        stdout: SplitParser { onRead: line => { var t = "" + line; if (t !== "") listProc._buf.push(t) } }
        onRunningChanged: if (!running) { root.items = listProc._buf; listProc._buf = [] }
    }
    function load() { listProc._buf = []; listProc.command = ["bash", "-c", "clipvault list"]; listProc.running = false; listProc.running = true }

    Process { id: copyProc }
    function copy(line) {
        // line passed as $1 (no shell injection); clipvault reproduces the exact stored content.
        copyProc.command = ["bash", "-c", "clipvault get \"$1\" | wl-copy", "vtl", "" + line]
        copyProc.running = false; copyProc.running = true
        UiState.clipboardOpen = false
    }
    function launchSel() { var l = root.filtered[list.currentIndex]; if (l !== undefined) root.copy(l) }
    function move(d) {
        var n = root.filtered.length; if (n === 0) return
        list.currentIndex = Math.max(0, Math.min(n - 1, list.currentIndex + d))
        list.positionViewAtIndex(list.currentIndex, ListView.Contain)
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, (VtlConfig.clipboardDim ? 0.4 : 0.0) * root.reveal)
        MouseArea { anchors.fill: parent; onClicked: UiState.clipboardOpen = false }
    }

    StyledRect {
        id: card
        width:  Math.min(VtlConfig.clipboardWidth, root.width - 80)
        height: Math.min(root.height - 120, 28 + 46 + 10 + VtlConfig.clipboardRows * 52)
        anchors.horizontalCenter: parent.horizontalCenter
        y: (root.height - height) / 2
        radius: Style.rCard; color: Colors.bgPrimary
        borderWidth: 1; borderColor: Style.chromeBorder
        opacity: root.reveal
        scale:   0.97 + 0.03 * root.reveal
        MouseArea { anchors.fill: parent }

        Column {
            anchors.fill: parent; anchors.margins: 14; spacing: 10

            StyledRect {
                width: parent.width; height: 46; radius: Style.rControl; color: Style.controlFill
                borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                Text { anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                       text: "󰅍"; color: Colors.fgMuted; font.pixelSize: 18; font.family: Style.font }
                TextInput {
                    id: search
                    anchors { left: parent.left; leftMargin: 46; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    color: Colors.fgBright; font.pixelSize: 16; font.family: Style.font; clip: true; focus: true
                    Keys.onDownPressed:   root.move(1)
                    Keys.onUpPressed:     root.move(-1)
                    Keys.onReturnPressed: root.launchSel()
                    Keys.onEnterPressed:  root.launchSel()
                    Keys.onEscapePressed: UiState.clipboardOpen = false
                    Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: search.text === ""
                           text: "Search clipboard…"; color: Colors.fgMuted; font: search.font }
                }
            }

            ListView {
                id: list
                width: parent.width; height: Math.max(0, parent.height - 56)
                clip: true; model: root.filtered
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 80
                delegate: StyledRect {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width; height: 50
                    radius: Style.rControl
                    color: row.index === list.currentIndex ? Style.accent
                         : (rHov.containsMouse ? Style.controlHover : "transparent")
                    Text {
                        anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: ("" + row.modelData).replace(/\s+/g, " ").trim()
                        color: row.index === list.currentIndex ? Colors.fgBright : Colors.fgPrimary
                        font.pixelSize: 13; font.family: Style.font; elide: Text.ElideRight; maximumLineCount: 1
                    }
                    MouseArea { id: rHov; anchors.fill: parent; hoverEnabled: true
                                onPositionChanged: list.currentIndex = row.index
                                onClicked: { list.currentIndex = row.index; root.launchSel() } }
                }
                Text { visible: root.filtered.length === 0; anchors.centerIn: parent
                       text: "Clipboard empty"; color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
            }
        }
    }
}
