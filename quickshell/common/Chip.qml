import ".."
import QtQuick

// Single auto-width selectable chip — wrap-friendly inside a Flow (transition pickers, direction
// arrows, monitor lists). For a fixed row of tabs/segments use Segmented instead.
//
// `removable: true` turns it into a token with an ✕ (a picked item you can take back out again,
// e.g. the modules assigned to a bar slot) and emits removed() instead of being a toggle.
StyledRect {
    id: c
    property string label:     ""
    property bool   selected:  false
    property bool   removable: false
    signal clicked()
    signal removed()
    width:        lbl.implicitWidth + 20 + (c.removable ? 22 : 0)
    height:       28
    radius:       Style.rControl
    color:        selected ? Style.selFill : (h.containsMouse ? Style.controlHover : Style.controlFill)
    borderWidth:  selected ? Style.selBorderW : Style.controlBorderW
    borderColor:  selected ? Style.selBorderColor : Style.controlBorderColor
    Behavior on color { ColorAnimation { duration: 100 } }

    Text { id: lbl
           anchors.verticalCenter: parent.verticalCenter
           x: c.removable ? 10 : Math.round((c.width - lbl.implicitWidth) / 2)
           text: c.label
           color: c.selected ? Style.selText : Colors.fgPrimary
           font.pixelSize: 12; font.family: Style.font }
    MouseArea { id: h; anchors.fill: parent; hoverEnabled: true; onClicked: c.clicked() }

    // Remove affordance — on top of the row-wide MouseArea, so the ✕ wins inside its own circle.
    StyledRect {
        visible: c.removable
        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
        width: 20; height: 20; radius: 10
        color: xh.containsMouse ? Style.tint(Colors.fgUrgent, 0.35) : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
        Text { anchors.centerIn: parent; text: "✕"
               color: xh.containsMouse ? Colors.fgBright : Colors.fgMuted
               font.pixelSize: 10; font.family: Style.font }
        MouseArea { id: xh; anchors.fill: parent; hoverEnabled: true; onClicked: c.removed() }
    }
}
