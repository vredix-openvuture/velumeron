pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

Row {
    spacing: 4

    Repeater {
        model: SystemTray.items
        delegate: Item {
            required property SystemTrayItem modelData
            implicitWidth:  20
            implicitHeight: 20

            IconImage {
                anchors.fill:      parent
                source:            parent.modelData.icon
                implicitSize:      16
                anchors.margins:   2
            }

            MouseArea {
                anchors.fill:    parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: event => {
                    if (event.button === Qt.LeftButton)
                        parent.modelData.activate()
                    else
                        parent.modelData.secondaryActivate()
                }
            }
        }
    }
}
