import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Session / power menu (replaces rofi/assets/session-menu.sh). A centred row of power actions over a
// dim backdrop; arrows/Tab move, Enter activates, Esc / click-out closes. One per screen; shows on the
// monitor focused at open (UiState.sessionMon). Toggled via the `session` IPC (Super+Ctrl+Q).
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool isOpen: UiState.sessionOpen
    readonly property bool active: isOpen && root.mon !== "" && root.mon === UiState.sessionMon

    readonly property var actions: UiState.sessionActions   // canonical shared list
    property int sel: 0

    property real reveal: 0
    onActiveChanged: { reveal = active ? 1 : 0; if (active) { root.sel = 0; focusScope.forceActiveFocus() } }
    Behavior on reveal { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    visible: active || root.reveal > 0.01

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-session"
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusiveZone: 0

    Process { id: proc }
    function run(cmd) { proc.command = ["bash", "-c", cmd]; proc.running = false; proc.running = true }
    function activate(i) {
        var a = root.actions[i]; if (!a) return
        UiState.sessionOpen = false     // close first, then run (detached command)
        root.run(a.cmd)
    }

    // Dim backdrop — click outside closes.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4 * root.reveal)
        MouseArea { anchors.fill: parent; onClicked: UiState.sessionOpen = false }
    }

    FocusScope {
        id: focusScope
        anchors.fill: parent
        Keys.onEscapePressed:  UiState.sessionOpen = false
        Keys.onLeftPressed:    root.sel = (root.sel - 1 + root.actions.length) % root.actions.length
        Keys.onRightPressed:   root.sel = (root.sel + 1) % root.actions.length
        Keys.onTabPressed:     root.sel = (root.sel + 1) % root.actions.length
        Keys.onBacktabPressed: root.sel = (root.sel - 1 + root.actions.length) % root.actions.length
        Keys.onReturnPressed:  root.activate(root.sel)
        Keys.onEnterPressed:   root.activate(root.sel)

        StyledRect {
            anchors.centerIn: parent
            width:  rowLay.implicitWidth + 48
            height: 150
            radius: Style.rCard
            color:  Colors.bgPrimary
            borderWidth: 1; borderColor: Style.chromeBorder
            opacity: root.reveal
            scale:   0.96 + 0.04 * root.reveal
            MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close

            Row {
                id: rowLay
                anchors.centerIn: parent
                spacing: 14
                Repeater {
                    model: root.actions
                    delegate: StyledRect {
                        id: btn
                        required property var modelData
                        required property int index
                        readonly property bool seld: root.sel === index
                        width: 96; height: 110; radius: Style.rControl
                        color: btn.seld ? Style.accent : (bHov.containsMouse ? Style.controlHover : Style.controlFill)
                        borderWidth: btn.seld ? 0 : Style.controlBorderW
                        borderColor: Style.controlBorderColor
                        Behavior on color { ColorAnimation { duration: 90 } }
                        Column {
                            anchors.centerIn: parent; spacing: 10
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: btn.modelData.icon
                                   color: btn.seld ? Colors.fgBright : Colors.fgPrimary
                                   font.pixelSize: 34; font.family: Style.font }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: btn.modelData.label
                                   color: btn.seld ? Colors.fgBright : Colors.fgMuted
                                   font.pixelSize: 12; font.family: Style.font }
                        }
                        MouseArea { id: bHov; anchors.fill: parent; hoverEnabled: true
                                    onPositionChanged: root.sel = btn.index
                                    onClicked: root.activate(btn.index) }
                    }
                }
            }
        }
    }
}
