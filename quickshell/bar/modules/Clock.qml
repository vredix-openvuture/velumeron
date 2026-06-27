import "../.."
import QtQuick

Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar

    property var now: new Date()

    implicitWidth:  label.implicitWidth
    implicitHeight: label.implicitHeight

    Row {
        id: label
        spacing: 0

        Text {
            text:           Qt.formatTime(root.now, "hh:mm")
            color:          Colors.fgBright
            font.family:    "Audiowide"
            font.pointSize: 12
            font.weight:    Font.Medium
            opacity:        hov.containsMouse || UiState.openDropdown === "clock" ? 1.0 : 0.85
            Behavior on opacity { NumberAnimation { duration: 80 } }
        }

        Text {
            text:           "   " + Qt.formatDate(root.now, "ddd dd")
            color:          Colors.fgMuted
            font.family:    "Audiowide"
            font.pointSize: 12
            opacity:        hov.containsMouse || UiState.openDropdown === "clock" ? 1.0 : 0.75
            Behavior on opacity { NumberAnimation { duration: 80 } }
        }
    }

    Timer {
        interval: 10000
        running:  true
        repeat:   true
        onTriggered: root.now = new Date()
    }

    MouseArea {
        id: hov
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked:    UiState.openDropdown = UiState.openDropdown === "clock" ? "" : "clock"
    }
}
