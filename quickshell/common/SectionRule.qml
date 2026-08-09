import ".."
import QtQuick

// A named divider: a short stub, the name, then a rule to the far edge. The network panel's "VPN"
// heading and the bluetooth panel's device groups had drawn this by hand, twice, eight lines each —
// which is how two panels start disagreeing about a heading by a pixel.
Item {
    id: sr
    property string text:    ""
    property string trailing: ""          // a count or a state, right-aligned on the rule

    width:  parent ? parent.width : 0
    height: 16

    Rectangle {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 12; height: 1
        color: Style.tint(Colors.boNormal, 0.55)
    }
    Text {
        id: name
        anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
        text: sr.text; color: Colors.fgMuted
        font.family: Style.font; font.pixelSize: 10; font.bold: true
        font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
    }
    Rectangle {
        anchors { left: name.right; leftMargin: 8; right: tail.left; rightMargin: sr.trailing !== "" ? 8 : 0
                  verticalCenter: parent.verticalCenter }
        height: 1
        color: Style.tint(Colors.boNormal, 0.55)
    }
    Text {
        id: tail
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: sr.trailing; color: Colors.fgMuted
        font.family: Style.font; font.pixelSize: 9
    }
}
