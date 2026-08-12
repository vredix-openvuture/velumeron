import ".."
import QtQuick

// A small pill that either states a choice or takes one. The popouts' only button shape, so a row
// of them reads as one control rather than a toolbar of odds and ends.
StyledRect {
    id: c
    property string label: ""
    property bool   on:    false
    property bool   ghost: false         // a second rank: present, but not the primary choice
    property string trailing: ""         // e.g. a chevron on a picker
    signal tap()

    implicitWidth:  row.implicitWidth + 20
    implicitHeight: 22
    width:  implicitWidth
    height: implicitHeight
    radius: height / 2
    color: c.on ? Style.tint(Colors.bgActive, 0.32)
         : c.ghost ? "transparent"
         : h.containsMouse ? Style.controlHover : Style.controlFill
    borderWidth: c.ghost ? Style.controlBorderW : 0
    borderColor: Style.controlBorderColor
    Behavior on color { ColorAnimation { duration: Style.ctrlMs } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: c.label
            color: c.on ? Colors.fgBright : Colors.fgMuted
            font.family: Style.font; font.pixelSize: 10
        }
        Text {
            visible: c.trailing !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: c.trailing
            color: c.on ? Colors.fgBright : Colors.fgMuted
            font.family: Style.font; font.pixelSize: 9
        }
    }
    MouseArea { id: h; anchors.fill: parent; hoverEnabled: true; onClicked: c.tap() }
}
