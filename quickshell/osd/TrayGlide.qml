pragma ComponentBehavior: Bound
import ".."
import QtQuick
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// System-tray icons gliding out of the bar on hover of the notiftray bell. Interactive (icons are
// clickable) and `keepOpenOnHover` so the cursor can travel from the bell into the pill to reach
// them. One per screen.
BarGlide {
    id: g
    mine:            UiState.trayMon === g.mon && g.mon !== ""
    shown:           UiState.trayHover
    edge:            UiState.trayEdge
    anchorX:         UiState.trayAnchorX
    anchorY:         UiState.trayAnchorY
    interactive:     true
    keepOpenOnHover: true

    Row {
        spacing: 10
        Repeater {
            model: SystemTray.items
            delegate: Item {
                id: tItem
                required property SystemTrayItem modelData
                width: 24; height: 24
                IconImage {
                    anchors.centerIn: parent
                    width: 22; height: 22
                    source: tItem.modelData.icon
                    implicitSize: 22
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
    }
}
