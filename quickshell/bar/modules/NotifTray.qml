pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray

Item {
    id: root

    // Set by LBar's ModSlot so the tray can unfold the right way per edge/position.
    property string barEdge:  "top"
    property string barGroup: "start"
    readonly property bool vert: barEdge === "left" || barEdge === "right"
    readonly property int  sz:   VtlConfig.barIconSize

    // The bell is the persistent anchor; the system-tray items unfold away from the bar edge.
    // In a sidebar the bell sits at the start end (top) only for the start group — otherwise at
    // the end (bottom of a sidebar / right of a horizontal bar), so the tray unfolds upward when
    // the module is at the bottom and downward when it's at the top. (Group anchoring in LBar
    // already grows the slot away from its edge, so the bell stays put and the icons appear.)
    readonly property bool bellFirst: vert && barGroup === "start"

    implicitWidth:  lay.implicitWidth
    implicitHeight: lay.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    property bool showTray: hoverArea.containsMouse

    function togglePanel() { notifProc.running = false; notifProc.running = true }

    Grid {
        id: lay
        anchors.centerIn: parent
        flow:    root.vert ? Grid.TopToBottom : Grid.LeftToRight
        columns: root.vert ? 1  : 99
        rows:    root.vert ? 99 : 1
        spacing: 4
        // Keep every icon (and the bell) centred on the bar's cross axis.
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment:   Grid.AlignVCenter

        // Bell on the start side (only a vertical start group); else after the tray items.
        Loader { active: root.bellFirst;  visible: active; sourceComponent: bell }

        Repeater {
            model: SystemTray.items
            delegate: Item {
                id: tItem
                required property SystemTrayItem modelData
                readonly property bool open: root.showTray
                // Reveal along the bar: width on a horizontal bar, height in a sidebar.
                implicitWidth:  root.vert ? root.sz : (open ? root.sz : 0)
                implicitHeight: root.vert ? (open ? root.sz : 0) : root.sz
                clip: true
                Behavior on implicitWidth  { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on implicitHeight { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                IconImage {
                    anchors.centerIn: parent
                    width:  root.sz
                    height: root.sz
                    source: tItem.modelData.icon
                    implicitSize: root.sz
                }
                MouseArea {
                    anchors.fill:    parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: event => {
                        if (event.button === Qt.LeftButton) tItem.modelData.activate()
                        else                                tItem.modelData.secondaryActivate()
                    }
                }
            }
        }

        Loader { active: !root.bellFirst; visible: active; sourceComponent: bell }
    }

    Component {
        id: bell
        Text {
            text:           "󰂜"
            color:          bellHover.containsMouse ? Colors.fgBright : Colors.fgPrimary
            font.family:    "FantasqueSansM Nerd Font"
            font.pixelSize: root.sz
            Behavior on color { ColorAnimation { duration: 100 } }

            MouseArea {
                id: bellHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked:    root.togglePanel()
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill:    lay
        hoverEnabled:    true
        acceptedButtons: Qt.NoButton
    }

    Process { id: notifProc; command: ["bash", "-c", "$VUTURELAND_DIR/bin/vutureland --panel-toggle"] }
}
