import ".."
import QtQuick

// Single auto-width selectable chip — wrap-friendly inside a Flow (transition pickers, direction
// arrows, monitor lists). For a fixed row of tabs/segments use Segmented instead.
StyledRect {
    id: c
    property string label:    ""
    property bool   selected: false
    signal clicked()
    width:        lbl.implicitWidth + 20
    height:       28
    radius:       Style.rControl
    color:        selected ? Style.selFill : (h.containsMouse ? Style.controlHover : Style.controlFill)
    borderWidth:  selected ? Style.selBorderW : Style.controlBorderW
    borderColor:  selected ? Style.selBorderColor : Style.controlBorderColor
    Behavior on color { ColorAnimation { duration: 100 } }

    Text { id: lbl; anchors.centerIn: parent; text: c.label
           color: c.selected ? Style.selText : Colors.fgPrimary
           font.pixelSize: 12; font.family: Style.font }
    MouseArea { id: h; anchors.fill: parent; hoverEnabled: true; onClicked: c.clicked() }
}
