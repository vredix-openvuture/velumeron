import ".."
import QtQuick

// The bare sliding switch, without a label — for rows that build their own layout around it
// (a menu header, a device row). For a plain "label + switch" settings row use Toggle, which is
// built on this one, so the two can never drift apart again: four places used to re-declare this
// 42×22 knob by hand, three of them with the wrong colours.
Rectangle {
    id: sw
    property bool on: false
    signal toggled()

    width: 42; height: 22; radius: 11
    color: sw.on ? Style.trackOn : Style.trackOff
    Behavior on color { ColorAnimation { duration: Style.ctrlMs } }

    Rectangle {
        width: 16; height: 16; radius: 8; color: Style.knob
        anchors.verticalCenter: parent.verticalCenter
        x: sw.on ? parent.width - width - 3 : 3
        Behavior on x { NumberAnimation { duration: Style.ctrlMs; easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; onClicked: sw.toggled() }
}
