import "../.."
import QtQuick

// One zone in the bar layout (Left / Center / Right).
// The module list is scrollable; the "+ Add" button is pinned to the bottom.
Rectangle {
    id: zone
    color: "transparent"

    property string zoneId:   ""
    property string label:    ""
    property var    modules:  []
    property var    labelFor: null
    signal remove(string key)
    signal addRequest()

    Rectangle {
        anchors { fill: parent; margins: 6 }
        color:  Colors.bgElement
        radius: 8
        clip:   true

        // Zone header label
        Text {
            id: zoneLabel
            anchors { top: parent.top; topMargin: 10; left: parent.left; leftMargin: 10 }
            text:           zone.label
            color:          Colors.fgMuted
            font.pixelSize: 10
            font.letterSpacing: 1.5
            font.family:    "FantasqueSansM Nerd Font"
        }

        // Add button — pinned to bottom
        Rectangle {
            id: addBtnRect
            anchors { bottom: parent.bottom; bottomMargin: 10; left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10 }
            height:       28
            radius:       6
            color:        addHov.containsMouse ? Colors.bgActive : "transparent"
            border.color: Colors.boNormal
            border.width: 1

            Text {
                anchors.centerIn: parent
                text:  "+ Add"
                color: addHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                font.pixelSize: 11
                font.family:    "FantasqueSansM Nerd Font"
            }

            MouseArea {
                id: addHov; anchors.fill: parent; hoverEnabled: true
                onClicked: zone.addRequest()
            }
        }

        // Scrollable module list
        Flickable {
            anchors {
                top:          zoneLabel.bottom; topMargin: 6
                bottom:       addBtnRect.top;   bottomMargin: 6
                left:         parent.left;       leftMargin: 10
                right:        parent.right;      rightMargin: 10
            }
            contentHeight: chipCol.implicitHeight
            clip:          true

            Column {
                id: chipCol
                width:   parent.width
                spacing: 4

                Repeater {
                    model: zone.modules
                    delegate: Rectangle {
                        readonly property string modKey: zone.modules[index] ?? ""
                        width:  chipCol.width
                        height: 30
                        color:  Colors.bgPrimary
                        radius: 6

                        Text {
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            text:           zone.labelFor ? zone.labelFor(modKey) : modKey
                            color:          Colors.fgPrimary
                            font.pixelSize: 12
                            font.family:    "FantasqueSansM Nerd Font"
                        }

                        Rectangle {
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            width: 22; height: 22; radius: 11
                            color: rmHov.containsMouse
                                   ? Qt.rgba(Colors.fgUrgent.r, Colors.fgUrgent.g, Colors.fgUrgent.b, 0.2)
                                   : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text:  "✕"
                                color: rmHov.containsMouse ? Colors.fgUrgent : Colors.fgMuted
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: rmHov; anchors.fill: parent; hoverEnabled: true
                                onClicked: zone.remove(modKey)
                            }
                        }
                    }
                }
            }
        }
    }
}
