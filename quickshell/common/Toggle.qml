import ".."
import QtQuick

// Label (+ optional sub-caption) with a sliding switch. `indent` nudges it right for sub-options.
Rectangle {
    id: tg
    property string label:  ""
    property string sub:    ""
    property bool   on:     false
    property bool   indent: false
    signal toggled()

    width:        parent ? parent.width - (indent ? 12 : 0) : 0
    x:            indent ? 12 : 0
    height:       tg.sub !== "" ? 46 : 38
    radius:       Style.rControl
    color:        Style.controlFill
    border.width: Style.controlBorderW
    border.color: Style.controlBorderColor

    Column {
        anchors { left: parent.left; leftMargin: 12; right: knob.left; rightMargin: 10
                  verticalCenter: parent.verticalCenter }
        spacing: 1
        Text { text: tg.label; color: Colors.fgPrimary; font.pixelSize: Style.fsLabel
               font.family: Style.font; elide: Text.ElideRight; width: parent.width }
        Text { visible: tg.sub !== ""; text: tg.sub; color: Colors.fgMuted; font.pixelSize: Style.fsSub
               font.family: Style.font; elide: Text.ElideRight; width: parent.width }
    }

    Rectangle {
        id: knob
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        width: 42; height: 22; radius: 11
        color: tg.on ? Style.trackOn : Style.trackOff
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 16; height: 16; radius: 8; color: Style.knob
            anchors.verticalCenter: parent.verticalCenter
            x: tg.on ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; onClicked: tg.toggled() }
    }
}
