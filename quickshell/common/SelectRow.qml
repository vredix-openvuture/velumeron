import ".."
import QtQuick

// Full-width selectable row with a ✓ when active (fixed-scheme list, auto-order list …).
Rectangle {
    id: r
    property string label:    ""
    property bool   selected: false
    signal clicked()
    width:        parent ? parent.width : 0
    height:       34
    radius:       Style.rControl
    color:        selected ? Style.selFill : (h.containsMouse ? Style.controlHover : Style.controlFill)
    border.width: selected ? Style.selBorderW : Style.controlBorderW
    border.color: selected ? Style.selBorderColor : Style.controlBorderColor
    Behavior on color { ColorAnimation { duration: 90 } }

    Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
           text: r.label; color: r.selected ? Style.selText : Colors.fgPrimary
           font.pixelSize: Style.fsLabel; font.family: Style.font }
    Text { visible: r.selected
           anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
           text: "✓"; color: Style.selText; font.pixelSize: 12; font.family: Style.font }
    MouseArea { id: h; anchors.fill: parent; hoverEnabled: true; onClicked: r.clicked() }
}
